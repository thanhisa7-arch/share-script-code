-- ScriptHub Pro schema for Supabase
-- Run once in Supabase Dashboard > SQL Editor > New query.
-- After running, promote your own account to admin using the final UPDATE below.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null default 'Member' check (char_length(username) between 1 and 32),
  bio text not null default '' check (char_length(bio) <= 240),
  avatar_url text,
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.scripts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 90),
  category text not null check (category in ('Roblox','Lua','HTML','JavaScript','Khác')),
  description text not null default '' check (char_length(description) <= 300),
  code text not null check (char_length(code) between 1 and 30000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.script_likes (
  id uuid primary key default gen_random_uuid(),
  script_id uuid not null references public.scripts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(script_id,user_id)
);

create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  script_id uuid not null references public.scripts(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 800),
  created_at timestamptz not null default now()
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  script_id uuid references public.scripts(id) on delete cascade,
  comment_id uuid references public.comments(id) on delete cascade,
  message text not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  script_id uuid not null references public.scripts(id) on delete cascade,
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null check (char_length(reason) between 1 and 100),
  details text not null default '' check (char_length(details) <= 500),
  status text not null default 'pending' check (status in ('pending','reviewed','resolved')),
  created_at timestamptz not null default now(),
  unique(script_id,reporter_id)
);

create index if not exists scripts_created_idx on public.scripts(created_at desc);
create index if not exists likes_script_idx on public.script_likes(script_id);
create index if not exists comments_script_idx on public.comments(script_id);
create index if not exists notifications_user_idx on public.notifications(user_id,created_at desc);
create index if not exists reports_status_idx on public.reports(status,created_at desc);

-- Create a profile automatically whenever a user signs up.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
  insert into public.profiles(id,username)
  values(new.id,coalesce(nullif(left(new.raw_user_meta_data->>'username',32),''),'Member'))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Notify the script owner when another user comments.
create or replace function public.notify_script_owner_on_comment()
returns trigger language plpgsql security definer set search_path=public
as $$
declare owner_id uuid; commenter_name text;
begin
  select author_id into owner_id from public.scripts where id=new.script_id;
  select username into commenter_name from public.profiles where id=new.author_id;
  if owner_id is not null and owner_id <> new.author_id then
    insert into public.notifications(user_id,actor_id,script_id,comment_id,message)
    values(owner_id,new.author_id,new.script_id,new.id,
      coalesce(commenter_name,'Someone') || ' đã bình luận vào script của bạn.');
  end if;
  return new;
end;
$$;

drop trigger if exists on_comment_notify_owner on public.comments;
create trigger on_comment_notify_owner after insert on public.comments
for each row execute procedure public.notify_script_owner_on_comment();

-- Keep updated_at current.
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at=now(); return new; end; $$;
drop trigger if exists scripts_updated_at on public.scripts;
create trigger scripts_updated_at before update on public.scripts
for each row execute procedure public.set_updated_at();

alter table public.profiles enable row level security;
alter table public.scripts enable row level security;
alter table public.script_likes enable row level security;
alter table public.comments enable row level security;
alter table public.notifications enable row level security;
alter table public.reports enable row level security;

-- Profiles: public read, owner updates only allowed profile fields.
drop policy if exists "Profiles are readable" on public.profiles;
create policy "Profiles are readable" on public.profiles for select to anon,authenticated using (true);
revoke update on public.profiles from authenticated;
grant update(username,bio,avatar_url) on public.profiles to authenticated;
drop policy if exists "Users update own profile" on public.profiles;
create policy "Users update own profile" on public.profiles for update to authenticated
using (id=auth.uid()) with check (id=auth.uid());

-- Scripts: everyone can read; signed-in users create; owners edit/delete; admins moderate.
drop policy if exists "Scripts are readable" on public.scripts;
create policy "Scripts are readable" on public.scripts for select to anon,authenticated using (true);
drop policy if exists "Signed in users create scripts" on public.scripts;
create policy "Signed in users create scripts" on public.scripts for insert to authenticated with check (author_id=auth.uid());
drop policy if exists "Owners and admins update scripts" on public.scripts;
create policy "Owners and admins update scripts" on public.scripts for update to authenticated
using (author_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.is_admin))
with check (author_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.is_admin));
drop policy if exists "Owners and admins delete scripts" on public.scripts;
create policy "Owners and admins delete scripts" on public.scripts for delete to authenticated
using (author_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.is_admin));

-- Likes.
drop policy if exists "Likes are readable" on public.script_likes;
create policy "Likes are readable" on public.script_likes for select to anon,authenticated using (true);
drop policy if exists "Users like as themselves" on public.script_likes;
create policy "Users like as themselves" on public.script_likes for insert to authenticated with check (user_id=auth.uid());
drop policy if exists "Users remove own likes" on public.script_likes;
create policy "Users remove own likes" on public.script_likes for delete to authenticated using (user_id=auth.uid());

-- Comments.
drop policy if exists "Comments are readable" on public.comments;
create policy "Comments are readable" on public.comments for select to anon,authenticated using (true);
drop policy if exists "Users comment as themselves" on public.comments;
create policy "Users comment as themselves" on public.comments for insert to authenticated with check (author_id=auth.uid());
drop policy if exists "Authors and admins delete comments" on public.comments;
create policy "Authors and admins delete comments" on public.comments for delete to authenticated
using (author_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.is_admin));

-- Notifications: only recipient can read/update their own notifications.
drop policy if exists "Users read own notifications" on public.notifications;
create policy "Users read own notifications" on public.notifications for select to authenticated using (user_id=auth.uid());
drop policy if exists "Users update own notifications" on public.notifications;
create policy "Users update own notifications" on public.notifications for update to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());
-- No client insert policy: notifications are inserted only by the database trigger.

-- Reports: users submit/read their own; admins read and update all.
drop policy if exists "Users read own reports and admins read all" on public.reports;
create policy "Users read own reports and admins read all" on public.reports for select to authenticated
using (reporter_id=auth.uid() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.is_admin));
drop policy if exists "Users submit reports as themselves" on public.reports;
create policy "Users submit reports as themselves" on public.reports for insert to authenticated with check (reporter_id=auth.uid());
drop policy if exists "Admins update reports" on public.reports;
create policy "Admins update reports" on public.reports for update to authenticated
using (exists(select 1 from public.profiles p where p.id=auth.uid() and p.is_admin))
with check (exists(select 1 from public.profiles p where p.id=auth.uid() and p.is_admin));

-- Promote your account to admin AFTER signing up.
-- Replace the email with the email address used for your ScriptHub account:
-- update public.profiles
-- set is_admin = true
-- where id = (select id from auth.users where email = 'YOUR_EMAIL@example.com');

-- Security note:
-- Do not expose service_role keys. Enable email confirmation and CAPTCHA/rate limiting
-- in Supabase Auth before opening the site publicly. Review reports and moderate content.
