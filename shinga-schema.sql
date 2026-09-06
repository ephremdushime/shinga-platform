-- ═══════════════════════════════════════════════════════════════
-- SHINGA Rwanda — Supabase Database Schema
-- Phase 1: Jobs + Workers
-- ═══════════════════════════════════════════════════════════════

-- ── EXTENSIONS ────────────────────────────────────────────────
create extension if not exists "uuid-ossp";
create extension if not exists "pg_trgm"; -- for full-text search

-- ── ENUMS ─────────────────────────────────────────────────────
create type job_type as enum (
  'daily',
  'weekly',
  'monthly',
  'contract',
  'permanent',
  'per_task'
);

create type job_category as enum (
  'professional',
  'health',
  'technology',
  'education',
  'domestic',
  'trades',
  'casual'
);

create type job_status as enum (
  'active',
  'paused',
  'filled',
  'expired',
  'removed'
);

create type worker_status as enum (
  'active',
  'unavailable',
  'suspended',
  'pending_review'
);

create type availability_type as enum (
  'full_time',
  'part_time',
  'weekdays',
  'weekends',
  'daily_gigs',
  'flexible'
);

create type application_status as enum (
  'pending',
  'viewed',
  'contacted',
  'hired',
  'rejected',
  'withdrawn'
);

-- ── DISTRICTS ─────────────────────────────────────────────────
create table districts (
  id          serial primary key,
  name        text not null unique,
  province    text not null,
  created_at  timestamptz default now()
);

insert into districts (name, province) values
  ('Gasabo',      'Kigali City'),
  ('Kicukiro',    'Kigali City'),
  ('Nyarugenge',  'Kigali City'),
  ('Burera',      'Northern Province'),
  ('Gakenke',     'Northern Province'),
  ('Gicumbi',     'Northern Province'),
  ('Musanze',     'Northern Province'),
  ('Rulindo',     'Northern Province'),
  ('Gisagara',    'Southern Province'),
  ('Huye',        'Southern Province'),
  ('Kamonyi',     'Southern Province'),
  ('Muhanga',     'Southern Province'),
  ('Nyamagabe',   'Southern Province'),
  ('Nyanza',      'Southern Province'),
  ('Nyaruguru',   'Southern Province'),
  ('Ruhango',     'Southern Province'),
  ('Bugesera',    'Eastern Province'),
  ('Gatsibo',     'Eastern Province'),
  ('Kayonza',     'Eastern Province'),
  ('Kirehe',      'Eastern Province'),
  ('Ngoma',       'Eastern Province'),
  ('Nyagatare',   'Eastern Province'),
  ('Rwamagana',   'Eastern Province'),
  ('Karongi',     'Western Province'),
  ('Ngororero',   'Western Province'),
  ('Nyabihu',     'Western Province'),
  ('Nyamasheke',  'Western Province'),
  ('Rubavu',      'Western Province'),
  ('Rutsiro',     'Western Province'),
  ('Rusizi',      'Western Province');

-- ── USERS (extends Supabase auth.users) ───────────────────────
create table profiles (
  id              uuid primary key references auth.users(id) on delete cascade,
  full_name       text not null,
  phone           text unique,
  phone_verified  boolean default false,
  avatar_url      text,
  role            text check (role in ('employer', 'worker', 'admin')) not null default 'employer',
  district_id     integer references districts(id),
  created_at      timestamptz default now(),
  updated_at      timestamptz default now()
);

-- ── WORKERS ───────────────────────────────────────────────────
create table workers (
  id              uuid primary key default uuid_generate_v4(),
  profile_id      uuid unique references profiles(id) on delete cascade,

  -- Identity
  full_name       text not null,
  phone           text not null,
  photo_url       text,

  -- Work details
  category        job_category not null,
  skill_title     text not null,          -- e.g. "House Cleaner", "Software Developer"
  skill_tags      text[],                 -- e.g. ['React', 'Node.js', 'PostgreSQL']
  bio             text,
  years_exp       integer default 0,
  availability    availability_type not null default 'flexible',

  -- Location
  district_id     integer references districts(id),
  sector          text,                   -- sub-district level
  can_travel      boolean default false,

  -- Rates
  rate_amount     numeric(12,2),
  rate_unit       text check (rate_unit in ('hour', 'day', 'week', 'month', 'task')),
  rate_negotiable boolean default true,

  -- Trust signals
  verified        boolean default false,
  id_verified     boolean default false,
  featured        boolean default false,
  featured_until  timestamptz,

  -- Stats (denormalized for speed)
  rating_avg      numeric(3,2) default 0,
  rating_count    integer default 0,
  jobs_completed  integer default 0,
  views_count     integer default 0,

  -- Status
  status          worker_status default 'active',
  created_at      timestamptz default now(),
  updated_at      timestamptz default now()
);

-- Full-text search index on workers
create index workers_search_idx on workers
  using gin(to_tsvector('english', coalesce(skill_title,'') || ' ' || coalesce(bio,'') || ' ' || coalesce(array_to_string(skill_tags,' '),'')));
create index workers_category_idx   on workers(category);
create index workers_district_idx   on workers(district_id);
create index workers_status_idx     on workers(status);
create index workers_featured_idx   on workers(featured, featured_until);
create index workers_rating_idx     on workers(rating_avg desc);

-- ── JOBS ──────────────────────────────────────────────────────
create table jobs (
  id              uuid primary key default uuid_generate_v4(),
  employer_id     uuid references profiles(id) on delete cascade,

  -- Content
  title           text not null,
  company_name    text,
  description     text not null,
  requirements    text,

  -- Classification
  category        job_category not null,
  job_type        job_type not null,
  skills_needed   text[],

  -- Location
  district_id     integer references districts(id),
  sector          text,
  remote_ok       boolean default false,

  -- Pay
  pay_amount      numeric(12,2),
  pay_max         numeric(12,2),          -- for ranges
  pay_unit        text check (pay_unit in ('hour', 'day', 'week', 'month', 'task', 'project')),
  pay_negotiable  boolean default true,

  -- Logistics
  start_date      date,
  duration        text,                   -- human-readable: "3 months", "1 day", etc.
  slots           integer default 1,      -- how many people needed

  -- Promotion
  featured        boolean default false,
  featured_until  timestamptz,
  urgent          boolean default false,

  -- Stats
  views_count     integer default 0,
  applications_count integer default 0,

  -- Status
  status          job_status default 'active',
  expires_at      timestamptz default (now() + interval '30 days'),
  created_at      timestamptz default now(),
  updated_at      timestamptz default now()
);

-- Full-text search index on jobs
create index jobs_search_idx on jobs
  using gin(to_tsvector('english', coalesce(title,'') || ' ' || coalesce(description,'') || ' ' || coalesce(company_name,'')));
create index jobs_category_idx    on jobs(category);
create index jobs_type_idx        on jobs(job_type);
create index jobs_district_idx    on jobs(district_id);
create index jobs_status_idx      on jobs(status);
create index jobs_featured_idx    on jobs(featured, featured_until);
create index jobs_created_idx     on jobs(created_at desc);

-- ── APPLICATIONS ──────────────────────────────────────────────
create table applications (
  id          uuid primary key default uuid_generate_v4(),
  job_id      uuid not null references jobs(id) on delete cascade,
  worker_id   uuid not null references workers(id) on delete cascade,
  cover_note  text,
  status      application_status default 'pending',
  viewed_at   timestamptz,
  created_at  timestamptz default now(),
  updated_at  timestamptz default now(),
  unique(job_id, worker_id)
);

create index applications_job_idx    on applications(job_id);
create index applications_worker_idx on applications(worker_id);
create index applications_status_idx on applications(status);

-- ── REVIEWS ───────────────────────────────────────────────────
create table reviews (
  id              uuid primary key default uuid_generate_v4(),
  worker_id       uuid not null references workers(id) on delete cascade,
  reviewer_id     uuid not null references profiles(id) on delete cascade,
  application_id  uuid references applications(id),
  rating          integer not null check (rating between 1 and 5),
  comment         text,
  created_at      timestamptz default now(),
  unique(worker_id, reviewer_id, application_id)
);

create index reviews_worker_idx on reviews(worker_id);

-- ── SAVED JOBS / WORKERS ──────────────────────────────────────
create table saved_jobs (
  profile_id  uuid references profiles(id) on delete cascade,
  job_id      uuid references jobs(id) on delete cascade,
  saved_at    timestamptz default now(),
  primary key (profile_id, job_id)
);

create table saved_workers (
  profile_id  uuid references profiles(id) on delete cascade,
  worker_id   uuid references workers(id) on delete cascade,
  saved_at    timestamptz default now(),
  primary key (profile_id, worker_id)
);

-- ── ANALYTICS (lightweight) ───────────────────────────────────
create table job_views (
  id          bigserial primary key,
  job_id      uuid references jobs(id) on delete cascade,
  viewer_ip   text,
  viewed_at   timestamptz default now()
);

create table worker_views (
  id          bigserial primary key,
  worker_id   uuid references workers(id) on delete cascade,
  viewer_ip   text,
  viewed_at   timestamptz default now()
);

-- ── FUNCTIONS ─────────────────────────────────────────────────

-- Auto-update updated_at on any row change
create or replace function update_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger trg_workers_updated before update on workers
  for each row execute function update_updated_at();
create trigger trg_jobs_updated before update on jobs
  for each row execute function update_updated_at();
create trigger trg_profiles_updated before update on profiles
  for each row execute function update_updated_at();

-- Recalculate worker rating when a review is inserted/updated
create or replace function recalc_worker_rating()
returns trigger as $$
begin
  update workers set
    rating_avg   = (select round(avg(rating)::numeric, 2) from reviews where worker_id = new.worker_id),
    rating_count = (select count(*) from reviews where worker_id = new.worker_id)
  where id = new.worker_id;
  return new;
end;
$$ language plpgsql;

create trigger trg_recalc_rating after insert or update on reviews
  for each row execute function recalc_worker_rating();

-- Increment job application count
create or replace function increment_application_count()
returns trigger as $$
begin
  update jobs set applications_count = applications_count + 1 where id = new.job_id;
  return new;
end;
$$ language plpgsql;

create trigger trg_app_count after insert on applications
  for each row execute function increment_application_count();

-- ── SEARCH FUNCTION ───────────────────────────────────────────
create or replace function search_jobs(
  keyword     text    default null,
  p_category  text    default null,
  p_job_type  text    default null,
  p_district  integer default null,
  p_limit     integer default 20,
  p_offset    integer default 0
)
returns table (
  id uuid, title text, company_name text, description text,
  category job_category, job_type job_type,
  district_id integer, pay_amount numeric, pay_unit text,
  featured boolean, urgent boolean, created_at timestamptz,
  applications_count integer, views_count integer
) as $$
begin
  return query
  select j.id, j.title, j.company_name, j.description,
         j.category, j.job_type, j.district_id,
         j.pay_amount, j.pay_unit, j.featured, j.urgent,
         j.created_at, j.applications_count, j.views_count
  from jobs j
  where j.status = 'active'
    and j.expires_at > now()
    and (keyword is null or to_tsvector('english', coalesce(j.title,'') || ' ' || coalesce(j.description,'')) @@ plainto_tsquery('english', keyword))
    and (p_category is null or j.category = p_category::job_category)
    and (p_job_type is null or j.job_type = p_job_type::job_type)
    and (p_district is null or j.district_id = p_district)
  order by j.featured desc, j.urgent desc, j.created_at desc
  limit p_limit offset p_offset;
end;
$$ language plpgsql;

create or replace function search_workers(
  keyword     text    default null,
  p_category  text    default null,
  p_district  integer default null,
  p_limit     integer default 20,
  p_offset    integer default 0
)
returns table (
  id uuid, full_name text, skill_title text, category job_category,
  district_id integer, rate_amount numeric, rate_unit text,
  rating_avg numeric, rating_count integer, verified boolean,
  featured boolean, availability availability_type, created_at timestamptz
) as $$
begin
  return query
  select w.id, w.full_name, w.skill_title, w.category,
         w.district_id, w.rate_amount, w.rate_unit,
         w.rating_avg, w.rating_count, w.verified,
         w.featured, w.availability, w.created_at
  from workers w
  where w.status = 'active'
    and (keyword is null or to_tsvector('english', coalesce(w.skill_title,'') || ' ' || coalesce(w.bio,'')) @@ plainto_tsquery('english', keyword))
    and (p_category is null or w.category = p_category::job_category)
    and (p_district is null or w.district_id = p_district)
  order by w.featured desc, w.rating_avg desc, w.created_at desc
  limit p_limit offset p_offset;
end;
$$ language plpgsql;

-- ── ROW LEVEL SECURITY ────────────────────────────────────────
alter table profiles     enable row level security;
alter table workers      enable row level security;
alter table jobs         enable row level security;
alter table applications enable row level security;
alter table reviews      enable row level security;

-- Profiles: own row only
create policy "profiles_own" on profiles for all using (auth.uid() = id);

-- Workers: public read, own write
create policy "workers_read"  on workers for select using (status = 'active');
create policy "workers_write" on workers for all   using (profile_id = auth.uid());

-- Jobs: public read, employer write
create policy "jobs_read"     on jobs for select using (status = 'active');
create policy "jobs_write"    on jobs for all    using (employer_id = auth.uid());

-- Applications: worker sees own, employer sees for their jobs
create policy "apps_worker"   on applications for all using (worker_id in (select id from workers where profile_id = auth.uid()));
create policy "apps_employer" on applications for select using (job_id in (select id from jobs where employer_id = auth.uid()));

-- Reviews: public read, own write
create policy "reviews_read"  on reviews for select using (true);
create policy "reviews_write" on reviews for insert using (reviewer_id = auth.uid());

-- ════════════════════════════════════════════════════════════════
-- END OF SCHEMA
-- ════════════════════════════════════════════════════════════════
