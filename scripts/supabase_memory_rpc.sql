create extension if not exists pgcrypto;

alter table public.memories
add column if not exists updated_at timestamptz default now();

alter table public.memories
add column if not exists resolved boolean default false;

alter table public.memories
add column if not exists digested boolean default false;

alter table public.memories
add column if not exists anchor boolean default false;

update public.memories
set resolved = false
where resolved is null;

update public.memories
set digested = false
where digested is null;

update public.memories
set anchor = false
where anchor is null;

create or replace function public.set_memories_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_memories_updated_at on public.memories;

create trigger trg_memories_updated_at
before update on public.memories
for each row
execute function public.set_memories_updated_at();

drop function if exists public.create_memory(
  text, text, text, text[], text[], text, double precision,
  double precision, double precision, boolean, timestamptz
);

drop function if exists public.create_memory(
  text, text, text, text[], text[], text, double precision,
  double precision, double precision, boolean, boolean, boolean, timestamptz
);

create or replace function public.create_memory(
  p_id text default null,
  p_title text default '未命名记忆',
  p_type text default 'dynamic',
  p_domain text[] default array['未分类'],
  p_tags text[] default '{}',
  p_content text default '',
  p_valence double precision default 0.5,
  p_arousal double precision default 0.5,
  p_importance double precision default 5.0,
  p_pinned boolean default false,
  p_resolved boolean default false,
  p_digested boolean default false,
  p_time timestamptz default now(),
  p_anchor boolean default false
)
returns public.memories
language plpgsql
security definer
set search_path = public
as $$
declare
  result public.memories;
  memory_id text;
  memory_type text;
begin
  memory_id := coalesce(nullif(p_id, ''), 'chatgpt_' || replace(gen_random_uuid()::text, '-', ''));
  memory_type := case
    when p_type in ('dynamic', 'permanent', 'feel', 'archived') then p_type
    else 'dynamic'
  end;

  insert into public.memories (
    id, title, type, domain, tags, content,
    valence, arousal, importance, pinned,
    resolved, digested, anchor,
    activation_count, created, last_active, updated_at, source, synced_at
  )
  values (
    memory_id, p_title, memory_type, p_domain, p_tags, p_content,
    greatest(0.0, least(1.0, p_valence)),
    greatest(0.0, least(1.0, p_arousal)),
    greatest(1.0, least(10.0, p_importance)),
    p_pinned,
    p_resolved, p_digested, p_anchor,
    1, p_time, p_time, p_time, 'chatgpt', p_time
  )
  on conflict (id) do update set
    title = excluded.title,
    type = excluded.type,
    domain = excluded.domain,
    tags = excluded.tags,
    content = excluded.content,
    valence = excluded.valence,
    arousal = excluded.arousal,
    importance = excluded.importance,
    pinned = excluded.pinned,
    resolved = excluded.resolved,
    digested = excluded.digested,
    anchor = excluded.anchor,
    last_active = excluded.last_active,
    updated_at = now(),
    source = 'chatgpt',
    synced_at = excluded.synced_at
  returning * into result;

  return result;
end;
$$;

revoke all on function public.create_memory(
  text, text, text, text[], text[], text, double precision,
  double precision, double precision, boolean, boolean, boolean, timestamptz, boolean
) from public;

grant execute on function public.create_memory(
  text, text, text, text[], text[], text, double precision,
  double precision, double precision, boolean, boolean, boolean, timestamptz, boolean
) to authenticated, service_role;
