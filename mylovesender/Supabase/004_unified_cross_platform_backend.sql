-- Unified MyLove backend contract for Android recipient and iOS sender.
-- Run after 001_mylove_schema.sql, 002_mailbox_pairing.sql and
-- 003_realtime_letters_media.sql.

-- A sender may read every non-deleted letter they created. This is required
-- for delivery/read-state synchronization in the sender app.
drop policy if exists "sender reads own letters" on public.letters;
create policy "sender reads own letters"
on public.letters for select to authenticated
using (
    sender_user_id = (select auth.uid())
);

-- Keep attachment metadata internally consistent.
create unique index if not exists letters_id_mailbox_idx
    on public.letters(id, mailbox_id);

alter table public.letter_attachments
    drop constraint if exists letter_attachments_letter_id_fkey;
alter table public.letter_attachments
    drop constraint if exists letter_attachments_letter_mailbox_fkey;
alter table public.letter_attachments
    add constraint letter_attachments_letter_mailbox_fkey
    foreign key (letter_id, mailbox_id)
    references public.letters(id, mailbox_id)
    on delete cascade;

grant update on public.letter_attachments to authenticated;

drop policy if exists "senders add letter attachments"
on public.letter_attachments;
create policy "senders add letter attachments"
on public.letter_attachments for insert to authenticated
with check (
    created_by = (select auth.uid())
    and exists (
        select 1
        from public.letters l
        where l.id = letter_attachments.letter_id
          and l.mailbox_id = letter_attachments.mailbox_id
          and l.sender_user_id = (select auth.uid())
          and l.deleted_at is null
    )
);

drop policy if exists "senders update own attachment metadata"
on public.letter_attachments;
create policy "senders update own attachment metadata"
on public.letter_attachments for update to authenticated
using (
    created_by = (select auth.uid())
)
with check (
    created_by = (select auth.uid())
    and exists (
        select 1
        from public.mailbox_members mm
        where mm.mailbox_id = letter_attachments.mailbox_id
          and mm.user_id = (select auth.uid())
          and mm.role = 'sender'
    )
);

drop policy if exists "senders delete own attachment metadata"
on public.letter_attachments;
create policy "senders delete own attachment metadata"
on public.letter_attachments for delete to authenticated
using (
    created_by = (select auth.uid())
    and exists (
        select 1
        from public.mailbox_members mm
        where mm.mailbox_id = letter_attachments.mailbox_id
          and mm.user_id = (select auth.uid())
          and mm.role = 'sender'
    )
);

drop policy if exists "mailbox senders update attachment objects"
on storage.objects;
create policy "mailbox senders update attachment objects"
on storage.objects for update to authenticated
using (
    bucket_id = 'letter-attachments'
    and exists (
        select 1
        from public.mailbox_members mm
        where mm.mailbox_id::text = (storage.foldername(name))[1]
          and mm.user_id = (select auth.uid())
          and mm.role = 'sender'
    )
)
with check (
    bucket_id = 'letter-attachments'
    and exists (
        select 1
        from public.mailbox_members mm
        where mm.mailbox_id::text = (storage.foldername(name))[1]
          and mm.user_id = (select auth.uid())
          and mm.role = 'sender'
    )
);

drop policy if exists "mailbox senders delete attachment objects"
on storage.objects;
create policy "mailbox senders delete attachment objects"
on storage.objects for delete to authenticated
using (
    bucket_id = 'letter-attachments'
    and exists (
        select 1
        from public.mailbox_members mm
        where mm.mailbox_id::text = (storage.foldername(name))[1]
          and mm.user_id = (select auth.uid())
          and mm.role = 'sender'
    )
);

create or replace function public.create_mailbox_letter_with_result(
    p_mailbox_id uuid,
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
#variable_conflict use_column
declare
    target_recipient uuid;
    normalized_status text;
begin
    if auth.uid() is null then
        raise exception 'not_authenticated';
    end if;
    if p_mailbox_id is null or p_client_request_id is null then
        raise exception 'missing_request_identity';
    end if;
    if length(trim(coalesce(p_title, ''))) = 0
       or length(trim(coalesce(p_body, ''))) = 0 then
        raise exception 'invalid_letter';
    end if;

    normalized_status := coalesce(nullif(trim(p_status), ''), 'published');
    if normalized_status not in ('draft', 'scheduled', 'published') then
        raise exception 'invalid_letter_status';
    end if;

    select m.recipient_user_id
    into target_recipient
    from public.mailboxes m
    join public.mailbox_members mm on mm.mailbox_id = m.id
    where m.id = p_mailbox_id
      and mm.user_id = auth.uid()
      and mm.role = 'sender';

    if target_recipient is null then
        raise exception 'not_paired';
    end if;

    insert into public.letters(
        id, owner_id, mailbox_id, client_request_id, sender_user_id,
        status, title, preview, body, date_label, published_at, created_at
    )
    values (
        gen_random_uuid(), target_recipient, p_mailbox_id,
        p_client_request_id, auth.uid(), normalized_status,
        trim(p_title), left(trim(coalesce(p_preview, '')), 280),
        trim(p_body), left(trim(coalesce(p_date_label, 'NEU')), 80),
        coalesce(p_published_at, now()), now()
    )
    on conflict (mailbox_id, client_request_id)
    where client_request_id is not null
    do update set
        title = excluded.title,
        preview = excluded.preview,
        body = excluded.body,
        date_label = excluded.date_label,
        published_at = excluded.published_at,
        status = excluded.status,
        sender_user_id = excluded.sender_user_id,
        deleted_at = null
    returning public.letters.id, public.letters.mailbox_id
    into letter_id, mailbox_id;
    return next;
end;
$$;

create or replace function public.publish_mailbox_letter(
    p_mailbox_id uuid,
    p_client_request_id uuid,
    p_status text,
    p_published_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
    if p_status not in ('scheduled', 'published') then
        raise exception 'invalid_letter_status';
    end if;

    update public.letters
    set status = p_status,
        published_at = coalesce(p_published_at, published_at)
    where mailbox_id = p_mailbox_id
      and client_request_id = p_client_request_id
      and sender_user_id = auth.uid()
      and deleted_at is null;

    if not found then
        raise exception 'letter_not_found';
    end if;
end;
$$;

create or replace function public.disconnect_sender_mailbox(
    p_mailbox_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
    delete from public.mailbox_members
    where mailbox_id = p_mailbox_id
      and user_id = auth.uid()
      and role = 'sender';

    if not found then
        raise exception 'membership_not_found';
    end if;
end;
$$;

-- Deleting is idempotent. A recipient may still have an old local copy after
-- a previous delete or an anonymous-session replacement. In that case the
-- desired server state is already reached and the client may remove its copy.
create or replace function public.delete_letter(letter_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
    update public.letters
    set deleted_at = coalesce(deleted_at, now())
    where id = letter_id
      and owner_id = auth.uid();
end;
$$;

revoke all on function public.create_mailbox_letter_with_result(
    uuid, uuid, text, text, text, text, timestamptz, text
) from public, anon;
revoke all on function public.publish_mailbox_letter(
    uuid, uuid, text, timestamptz
) from public, anon;
revoke all on function public.disconnect_sender_mailbox(uuid)
from public, anon;
revoke all on function public.delete_letter(uuid)
from public, anon;

grant execute on function public.create_mailbox_letter_with_result(
    uuid, uuid, text, text, text, text, timestamptz, text
) to authenticated;
grant execute on function public.publish_mailbox_letter(
    uuid, uuid, text, timestamptz
) to authenticated;
grant execute on function public.disconnect_sender_mailbox(uuid)
to authenticated;
grant execute on function public.delete_letter(uuid)
to authenticated;

-- All current sender clients use the mailbox-explicit RPC above.
revoke execute on function public.create_mailbox_letter(
    uuid, text, text, text, text, timestamptz
) from authenticated;

-- Make newly created RPC signatures immediately visible to PostgREST.
notify pgrst, 'reload schema';
