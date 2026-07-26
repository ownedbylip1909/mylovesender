-- MyLove mailbox pairing backend.
-- Run after 001_mylove_schema.sql in Supabase Dashboard > SQL Editor.

create extension if not exists pgcrypto;

create table if not exists public.mailboxes (
    id uuid primary key default gen_random_uuid(),
    recipient_user_id uuid not null references auth.users(id) on delete cascade,
    display_name text not null default 'Bella',
    created_at timestamptz not null default now()
);

create unique index if not exists mailboxes_one_per_recipient_idx
    on public.mailboxes(recipient_user_id);

create table if not exists public.mailbox_members (
    mailbox_id uuid not null references public.mailboxes(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    role text not null check (role in ('recipient', 'sender')),
    created_at timestamptz not null default now(),
    primary key (mailbox_id, user_id, role)
);

create table if not exists public.mailbox_pairing_codes (
    id uuid primary key default gen_random_uuid(),
    mailbox_id uuid not null references public.mailboxes(id) on delete cascade,
    code_hash bytea not null unique,
    expires_at timestamptz not null,
    used_at timestamptz,
    created_by uuid not null references auth.users(id) on delete cascade,
    created_at timestamptz not null default now(),
    check (expires_at > created_at)
);

alter table public.letters
    add column if not exists mailbox_id uuid
    references public.mailboxes(id) on delete cascade;
alter table public.letters
    add column if not exists client_request_id uuid;

create unique index if not exists letters_mailbox_client_request_idx
    on public.letters(mailbox_id, client_request_id)
    where client_request_id is not null;

alter table public.mailboxes enable row level security;
alter table public.mailbox_members enable row level security;
alter table public.mailbox_pairing_codes enable row level security;
alter table public.letters enable row level security;

revoke all on public.mailboxes from anon;
revoke all on public.mailbox_members from anon;
revoke all on public.mailbox_pairing_codes from anon;
revoke all on public.letters from anon;

grant select on public.mailboxes to authenticated;
grant select on public.mailbox_members to authenticated;
grant select on public.letters to authenticated;

drop policy if exists "members can read their mailboxes" on public.mailboxes;
create policy "members can read their mailboxes"
on public.mailboxes for select to authenticated
using (
    recipient_user_id = (select auth.uid())
    or exists (
        select 1
        from public.mailbox_members mm
        where mm.mailbox_id = mailboxes.id
          and mm.user_id = (select auth.uid())
    )
);

-- Do not query mailbox_members again inside its own policy: that causes
-- PostgreSQL RLS recursion. Each user only needs their own membership rows.
drop policy if exists "members can read their membership" on public.mailbox_members;
create policy "members can read their membership"
on public.mailbox_members for select to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "recipient reads published mailbox letters" on public.letters;
create policy "recipient reads published mailbox letters"
on public.letters for select to authenticated
using (
    published_at <= now()
    and exists (
        select 1
        from public.mailboxes m
        where m.id = letters.mailbox_id
          and m.recipient_user_id = (select auth.uid())
    )
);

create or replace function public.ensure_recipient_mailbox(
    display_name text default 'Bella'
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
    target_mailbox uuid;
begin
    if auth.uid() is null then
        raise exception 'not_authenticated';
    end if;

    insert into public.mailboxes(recipient_user_id, display_name)
    values (
        auth.uid(),
        coalesce(nullif(trim(display_name), ''), 'Bella')
    )
    on conflict (recipient_user_id) do nothing;

    select id
    into target_mailbox
    from public.mailboxes
    where recipient_user_id = auth.uid();

    insert into public.mailbox_members(mailbox_id, user_id, role)
    values (target_mailbox, auth.uid(), 'recipient')
    on conflict do nothing;
end;
$$;

create or replace function public.create_mailbox_pairing_code(
    pairing_code text,
    valid_for_minutes int default 30
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
    normalized text;
    target_mailbox uuid;
begin
    if auth.uid() is null then
        raise exception 'not_authenticated';
    end if;

    normalized := upper(regexp_replace(
        coalesce(pairing_code, ''),
        '[^A-Z0-9]',
        '',
        'g'
    ));
    if length(normalized) < 12 or length(normalized) > 32 then
        raise exception 'invalid_pairing_code';
    end if;
    if valid_for_minutes < 5 or valid_for_minutes > 120 then
        raise exception 'invalid_expiry';
    end if;

    perform public.ensure_recipient_mailbox('Bella');

    select id
    into target_mailbox
    from public.mailboxes
    where recipient_user_id = auth.uid();

    -- Keep only one currently valid code for a mailbox.
    update public.mailbox_pairing_codes
    set used_at = now()
    where mailbox_id = target_mailbox
      and used_at is null;

    insert into public.mailbox_pairing_codes(
        mailbox_id,
        code_hash,
        expires_at,
        created_by
    )
    values (
        target_mailbox,
        digest(normalized, 'sha256'),
        now() + make_interval(mins => valid_for_minutes),
        auth.uid()
    );
end;
$$;

create or replace function public.claim_mailbox_pairing_code(
    pairing_code text
)
returns table (recipient_name text, role text)
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
    normalized text;
    matched_code uuid;
    target_mailbox uuid;
begin
    if auth.uid() is null then
        raise exception 'not_authenticated';
    end if;

    normalized := upper(regexp_replace(
        coalesce(pairing_code, ''),
        '[^A-Z0-9]',
        '',
        'g'
    ));
    if length(normalized) < 12 or length(normalized) > 32 then
        raise exception 'invalid_pairing_code';
    end if;

    select pc.id, pc.mailbox_id
    into matched_code, target_mailbox
    from public.mailbox_pairing_codes pc
    where pc.code_hash = digest(normalized, 'sha256')
      and pc.used_at is null
      and pc.expires_at > now()
    for update;

    if matched_code is null then
        raise exception 'invalid_pairing_code';
    end if;

    insert into public.mailbox_members(mailbox_id, user_id, role)
    values (target_mailbox, auth.uid(), 'sender')
    on conflict do nothing;

    update public.mailbox_pairing_codes
    set used_at = now()
    where id = matched_code;

    return query
    select m.display_name, 'sender'::text
    from public.mailboxes m
    where m.id = target_mailbox;
end;
$$;

create or replace function public.create_mailbox_letter(
    client_request_id uuid,
    title text,
    preview text,
    body text,
    date_label text,
    published_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
    target_mailbox uuid;
    target_recipient uuid;
begin
    if auth.uid() is null then
        raise exception 'not_authenticated';
    end if;
    if client_request_id is null then
        raise exception 'missing_client_request_id';
    end if;
    if length(trim(coalesce(title, ''))) = 0
       or length(trim(coalesce(body, ''))) = 0 then
        raise exception 'invalid_letter';
    end if;

    select mm.mailbox_id, m.recipient_user_id
    into target_mailbox, target_recipient
    from public.mailbox_members mm
    join public.mailboxes m on m.id = mm.mailbox_id
    where mm.user_id = auth.uid()
      and mm.role = 'sender'
    order by mm.created_at asc
    limit 1;

    if target_mailbox is null then
        raise exception 'not_paired';
    end if;

    insert into public.letters(
        id,
        owner_id,
        mailbox_id,
        client_request_id,
        sender_user_id,
        status,
        title,
        preview,
        body,
        date_label,
        published_at,
        created_at
    )
    values (
        gen_random_uuid(),
        target_recipient,
        target_mailbox,
        create_mailbox_letter.client_request_id,
        auth.uid(),
        case when coalesce(create_mailbox_letter.published_at, now()) > now()
             then 'scheduled'
             else 'published'
        end,
        trim(create_mailbox_letter.title),
        left(trim(coalesce(create_mailbox_letter.preview, '')), 280),
        trim(create_mailbox_letter.body),
        left(trim(coalesce(create_mailbox_letter.date_label, 'NEU')), 80),
        coalesce(create_mailbox_letter.published_at, now()),
        now()
    )
    on conflict (mailbox_id, client_request_id)
    where client_request_id is not null
    do update set
        title = excluded.title,
        preview = excluded.preview,
        body = excluded.body,
        date_label = excluded.date_label,
        published_at = excluded.published_at,
        status = excluded.status;
end;
$$;

-- Optional RPC for iOS attachment uploads. Existing create_mailbox_letter remains supported.
create or replace function public.create_mailbox_letter_with_result(
    p_client_request_id uuid,
    p_title text,
    p_preview text,
    p_body text,
    p_date_label text,
    p_published_at timestamptz,
    p_status text default 'published'
)
returns table (letter_id uuid, mailbox_id uuid)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
    target_mailbox uuid;
    target_recipient uuid;
    normalized_status text;
begin
    if auth.uid() is null then
        raise exception 'not_authenticated';
    end if;
    if p_client_request_id is null then
        raise exception 'missing_client_request_id';
    end if;
    if length(trim(coalesce(p_title, ''))) = 0
       or length(trim(coalesce(p_body, ''))) = 0 then
        raise exception 'invalid_letter';
    end if;

    normalized_status := coalesce(nullif(trim(p_status), ''), 'published');
    if normalized_status not in ('draft', 'scheduled', 'published') then
        raise exception 'invalid_letter_status';
    end if;

    select mm.mailbox_id, m.recipient_user_id
    into target_mailbox, target_recipient
    from public.mailbox_members mm
    join public.mailboxes m on m.id = mm.mailbox_id
    where mm.user_id = auth.uid()
      and mm.role = 'sender'
    order by mm.created_at asc
    limit 1;

    if target_mailbox is null then
        raise exception 'not_paired';
    end if;

    insert into public.letters(
        id,
        owner_id,
        mailbox_id,
        client_request_id,
        sender_user_id,
        status,
        title,
        preview,
        body,
        date_label,
        published_at,
        created_at
    )
    values (
        gen_random_uuid(),
        target_recipient,
        target_mailbox,
        p_client_request_id,
        auth.uid(),
        normalized_status,
        trim(p_title),
        left(trim(coalesce(p_preview, '')), 280),
        trim(p_body),
        left(trim(coalesce(p_date_label, 'NEU')), 80),
        coalesce(p_published_at, now()),
        now()
    )
    on conflict (mailbox_id, client_request_id)
    where client_request_id is not null
    do update set
        title = excluded.title,
        preview = excluded.preview,
        body = excluded.body,
        date_label = excluded.date_label,
        published_at = excluded.published_at,
        status = excluded.status
    returning public.letters.id, public.letters.mailbox_id
    into letter_id, mailbox_id;

    return next;
end;
$$;

-- SECURITY DEFINER functions must not retain the default PUBLIC execute grant.
revoke all on function public.ensure_recipient_mailbox(text) from public, anon;
revoke all on function public.create_mailbox_pairing_code(text, int) from public, anon;
revoke all on function public.claim_mailbox_pairing_code(text) from public, anon;
revoke all on function public.create_mailbox_letter(
    uuid, text, text, text, text, timestamptz
) from public, anon;
revoke all on function public.create_mailbox_letter_with_result(
    uuid, text, text, text, text, timestamptz, text
) from public, anon;

grant execute on function public.ensure_recipient_mailbox(text) to authenticated;
grant execute on function public.create_mailbox_pairing_code(text, int) to authenticated;
grant execute on function public.claim_mailbox_pairing_code(text) to authenticated;
grant execute on function public.create_mailbox_letter(
    uuid, text, text, text, text, timestamptz
) to authenticated;
grant execute on function public.create_mailbox_letter_with_result(
    uuid, text, text, text, text, timestamptz, text
) to authenticated;
