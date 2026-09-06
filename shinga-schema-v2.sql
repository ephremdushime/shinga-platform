-- ═══════════════════════════════════════════════════════════════
-- SHINGA — Schema Patch v2
-- Feature 1: GPS Nearby Search (PostGIS)
-- Feature 2: Slot-Based Application System + Waitlist
-- Run this in Supabase SQL Editor AFTER the main schema
-- ═══════════════════════════════════════════════════════════════

-- ── FEATURE 1: POSTGIS + GPS LOCATION ─────────────────────────

-- Enable PostGIS (Supabase supports this natively)
create extension if not exists postgis;

-- Add GPS coordinates to workers table
alter table workers
  add column if not exists latitude        double precision,
  add column if not exists longitude       double precision,
  add column if not exists location        geography(Point, 4326),  -- PostGIS point
  add column if not exists location_updated_at timestamptz,
  add column if not exists available_now   boolean default false,   -- "I'm ready to work today"
  add column if not exists available_now_updated_at timestamptz;

-- Add GPS coordinates to jobs table (where the work is)
alter table jobs
  add column if not exists latitude        double precision,
  add column if not exists longitude       double precision,
  add column if not exists job_location    geography(Point, 4326),
  add column if not exists urgent          boolean default false,    -- "Need someone today"
  add column if not exists urgent_until    timestamptz;             -- auto-expires urgent flag

-- Spatial index for fast radius queries
create index if not exists workers_location_idx
  on workers using gist(location);

create index if not exists jobs_location_idx
  on jobs using gist(job_location);

create index if not exists workers_available_idx
  on workers(available_now, status)
  where available_now = true and status = 'active';

-- ── UPDATE LOCATION FUNCTION ──────────────────────────────────
-- Called when worker updates their location from the app
create or replace function update_worker_location(
  p_worker_id uuid,
  p_lat       double precision,
  p_lng       double precision
) returns void as $$
begin
  update workers set
    latitude             = p_lat,
    longitude            = p_lng,
    location             = ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
    location_updated_at  = now()
  where id = p_worker_id;
end;
$$ language plpgsql security definer;

-- ── SEARCH WORKERS NEARBY ─────────────────────────────────────
-- Returns workers within radius_km of a GPS point,
-- sorted by distance (closest first)
create or replace function search_workers_nearby(
  p_lat        double precision,
  p_lng        double precision,
  p_radius_km  double precision default 5.0,
  p_category   text             default null,
  p_keyword    text             default null,
  p_available_now boolean       default false,
  p_limit      integer          default 20,
  p_offset     integer          default 0
) returns table(
  id              uuid,
  full_name       text,
  skill_title     text,
  category        job_category,
  district_id     integer,
  rate_amount     numeric,
  rate_unit       text,
  rating_avg      numeric,
  rating_count    integer,
  verified        boolean,
  available_now   boolean,
  latitude        double precision,
  longitude       double precision,
  distance_km     double precision,
  location_updated_at timestamptz
) as $$
declare
  search_point geography;
begin
  search_point := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography;

  return query
  select
    w.id,
    w.full_name,
    w.skill_title,
    w.category,
    w.district_id,
    w.rate_amount,
    w.rate_unit,
    w.rating_avg,
    w.rating_count,
    w.verified,
    w.available_now,
    w.latitude,
    w.longitude,
    -- Distance in km, rounded to 1 decimal
    round((ST_Distance(w.location, search_point) / 1000.0)::numeric, 1)::double precision as distance_km,
    w.location_updated_at
  from workers w
  where
    w.status   = 'active'
    and w.location is not null
    -- Only within radius
    and ST_DWithin(w.location, search_point, p_radius_km * 1000)
    -- Optional filters
    and (p_category is null or w.category = p_category::job_category)
    and (p_available_now = false or w.available_now = true)
    and (p_keyword is null or
         to_tsvector('english', coalesce(w.skill_title,'') || ' ' || coalesce(w.bio,''))
         @@ plainto_tsquery('english', p_keyword))
  order by
    -- Available now first, then by distance
    w.available_now desc,
    ST_Distance(w.location, search_point) asc
  limit p_limit offset p_offset;
end;
$$ language plpgsql;

-- ── SEARCH URGENT JOBS NEARBY ─────────────────────────────────
create or replace function search_jobs_nearby(
  p_lat       double precision,
  p_lng       double precision,
  p_radius_km double precision default 10.0,
  p_category  text             default null,
  p_job_type  text             default null,
  p_limit     integer          default 20,
  p_offset    integer          default 0
) returns table(
  id              uuid,
  title           text,
  company_name    text,
  category        job_category,
  job_type        job_type,
  pay_amount      numeric,
  pay_unit        text,
  slots           integer,
  slots_filled    integer,
  slots_remaining integer,
  urgent          boolean,
  distance_km     double precision,
  latitude        double precision,
  longitude       double precision,
  created_at      timestamptz
) as $$
declare
  search_point geography;
begin
  search_point := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography;

  return query
  select
    j.id,
    j.title,
    j.company_name,
    j.category,
    j.job_type,
    j.pay_amount,
    j.pay_unit,
    j.slots,
    j.slots_filled,
    (j.slots - j.slots_filled) as slots_remaining,
    j.urgent,
    round((ST_Distance(j.job_location, search_point) / 1000.0)::numeric, 1)::double precision as distance_km,
    j.latitude,
    j.longitude,
    j.created_at
  from jobs j
  where
    j.status       = 'active'
    and j.job_location is not null
    and j.slots_filled < j.slots  -- has open slots
    and ST_DWithin(j.job_location, search_point, p_radius_km * 1000)
    and (p_category is null or j.category = p_category::job_category)
    and (p_job_type is null or j.job_type = p_job_type::job_type)
  order by
    j.urgent desc,
    ST_Distance(j.job_location, search_point) asc,
    j.created_at desc
  limit p_limit offset p_offset;
end;
$$ language plpgsql;

-- ══════════════════════════════════════════════════════════════
-- FEATURE 2: SLOT-BASED APPLICATION SYSTEM + WAITLIST
-- ══════════════════════════════════════════════════════════════

-- ── ADD SLOT TRACKING TO JOBS ─────────────────────────────────
alter table jobs
  add column if not exists slots_filled     integer default 0,
  add column if not exists slots_max_apps   integer default null,  -- null = auto (slots × 3)
  add column if not exists app_buffer_mult  integer default 3;     -- multiplier for max apps

-- Computed max applications = slots × buffer (e.g. 1 slot × 3 = max 3 apps)
-- If admin sets slots_max_apps manually, use that instead

-- ── ADD SLOT TRACKING TO APPLICATIONS ────────────────────────
alter table applications
  add column if not exists is_waitlist   boolean default false,  -- true = on waitlist (free)
  add column if not exists waitlist_pos  integer,                -- position in waitlist
  add column if not exists notified_at   timestamptz;            -- when waitlist SMS was sent

-- ── WAITLIST TABLE ────────────────────────────────────────────
create table if not exists job_waitlist (
  id          uuid primary key default uuid_generate_v4(),
  job_id      uuid not null references jobs(id) on delete cascade,
  worker_id   uuid not null references workers(id) on delete cascade,
  phone       text not null,                   -- snapshot for SMS
  position    integer not null,                -- 1 = next in line
  status      text default 'waiting'
              check (status in ('waiting','notified','converted','expired')),
  notified_at timestamptz,
  created_at  timestamptz default now(),
  unique(job_id, worker_id)
);

create index if not exists waitlist_job_idx on job_waitlist(job_id, position);
create index if not exists waitlist_status_idx on job_waitlist(status);

-- ── PLATFORM SETTINGS (for admin-configurable values) ─────────
create table if not exists platform_settings (
  key         text primary key,
  value       text not null,
  label       text,
  updated_at  timestamptz default now()
);

-- Default settings
insert into platform_settings (key, value, label) values
  ('app_buffer_multiplier', '3',    'Max applications = slots × this number'),
  ('waitlist_sms_enabled',  'true', 'Send SMS to waitlist when slot opens'),
  ('urgent_radius_km',      '5',    'Default radius for urgent job SMS blast (km)'),
  ('available_now_hours',   '8',    'Hours before "Available Now" auto-expires')
on conflict (key) do nothing;

-- ── FUNCTION: CAN WORKER APPLY? ───────────────────────────────
-- Returns: 'open' | 'waitlist' | 'closed' | 'already_applied' | 'filled'
create or replace function check_application_eligibility(
  p_job_id    uuid,
  p_worker_id uuid
) returns text as $$
declare
  v_job           record;
  v_current_apps  integer;
  v_max_apps      integer;
  v_already       boolean;
begin
  -- Get job details
  select slots, slots_filled, slots_max_apps, app_buffer_mult, status
  into v_job
  from jobs where id = p_job_id;

  if not found then return 'not_found'; end if;
  if v_job.status != 'active' then return 'closed'; end if;

  -- Check if all slots are filled (hired)
  if v_job.slots_filled >= v_job.slots then return 'filled'; end if;

  -- Check if worker already applied or waitlisted
  select exists(
    select 1 from applications
    where job_id = p_job_id and worker_id = p_worker_id
  ) or exists(
    select 1 from job_waitlist
    where job_id = p_job_id and worker_id = p_worker_id
  ) into v_already;

  if v_already then return 'already_applied'; end if;

  -- Calculate max applications (slots × buffer, or manual override)
  v_max_apps := coalesce(
    v_job.slots_max_apps,
    v_job.slots * v_job.app_buffer_mult
  );

  -- Count current paid applications (not waitlist)
  select count(*) into v_current_apps
  from applications
  where job_id = p_job_id and is_waitlist = false
    and status not in ('withdrawn', 'rejected');

  -- Decision
  if v_current_apps < v_max_apps then
    return 'open';       -- can apply (pay RWF 500)
  else
    return 'waitlist';   -- queue full, join waitlist free
  end if;
end;
$$ language plpgsql;

-- ── FUNCTION: MARK SLOT FILLED (called after "Mark as Hired") ─
create or replace function fill_job_slot(
  p_job_id        uuid,
  p_application_id uuid
) returns void as $$
declare
  v_job        record;
  v_next       record;
begin
  -- Update application status
  update applications set status = 'hired', updated_at = now()
  where id = p_application_id;

  -- Increment slots filled
  update jobs
  set slots_filled = slots_filled + 1,
      updated_at   = now()
  where id = p_job_id
  returning slots, slots_filled into v_job;

  -- If all slots filled → close the job
  if v_job.slots_filled >= v_job.slots then
    update jobs set status = 'filled', updated_at = now()
    where id = p_job_id;

    -- Expire all remaining pending applications
    update applications
    set status = 'rejected', updated_at = now()
    where job_id = p_job_id
      and status = 'pending';

    -- Expire waitlist
    update job_waitlist
    set status = 'expired'
    where job_id = p_job_id and status = 'waiting';

  else
    -- Slots still open — notify next waitlist person
    select jw.*, w.phone as worker_phone
    into v_next
    from job_waitlist jw
    join workers w on w.id = jw.worker_id
    where jw.job_id = p_job_id
      and jw.status = 'waiting'
    order by jw.position asc
    limit 1;

    if found then
      -- Mark as notified (SMS sent externally via Edge Function)
      update job_waitlist
      set status = 'notified', notified_at = now()
      where id = v_next.id;
    end if;
  end if;
end;
$$ language plpgsql security definer;

-- ── TRIGGER: AUTO-UPDATE slots_filled ON HIRE ─────────────────
-- Also auto-close job when slots fill
create or replace function trg_application_hired() returns trigger as $$
begin
  if NEW.status = 'hired' and OLD.status != 'hired' then
    perform fill_job_slot(NEW.job_id, NEW.id);
  end if;
  return NEW;
end;
$$ language plpgsql;

drop trigger if exists application_hired_trg on applications;
create trigger application_hired_trg
  after update on applications
  for each row execute function trg_application_hired();

-- ── TRIGGER: AUTO-UPDATE available_now EXPIRY ─────────────────
-- Workers who set "Available Now" auto-expire after 8 hours
create or replace function trg_expire_available_now() returns trigger as $$
begin
  if NEW.available_now = true then
    NEW.available_now_updated_at := now();
  end if;
  return NEW;
end;
$$ language plpgsql;

drop trigger if exists worker_available_now_trg on workers;
create trigger worker_available_now_trg
  before update on workers
  for each row execute function trg_expire_available_now();

-- Cron job to expire "Available Now" after 8 hours
-- Add to Supabase → Edge Functions → Cron:
-- Schedule: every 30 minutes → "0,30 * * * *"
-- SQL: update workers set available_now = false
--      where available_now = true
--      and available_now_updated_at < now() - interval '8 hours';

-- ── TRIGGER: AUTO-REOPEN SLOTS ON REJECTION ───────────────────
create or replace function trg_application_rejected() returns trigger as $$
declare v_job record;
begin
  if NEW.status in ('rejected','withdrawn') and OLD.status = 'hired' then
    -- A previously hired worker was rejected/withdrew → reopen slot
    update jobs
    set slots_filled = greatest(0, slots_filled - 1),
        status       = 'active',
        updated_at   = now()
    where id = NEW.job_id
    returning slots, slots_filled into v_job;
  end if;
  return NEW;
end;
$$ language plpgsql;

drop trigger if exists application_rejected_trg on applications;
create trigger application_rejected_trg
  after update on applications
  for each row execute function trg_application_rejected();

-- ── VIEW: JOB APPLICATION STATUS (for UI) ─────────────────────
create or replace view job_application_status as
select
  j.id                                          as job_id,
  j.title,
  j.slots,
  j.slots_filled,
  (j.slots - j.slots_filled)                   as slots_remaining,
  coalesce(j.slots_max_apps, j.slots * j.app_buffer_mult) as max_applications,
  count(a.id) filter (where a.is_waitlist = false
    and a.status not in ('withdrawn','rejected')) as current_applications,
  count(w.id) filter (where w.status = 'waiting') as waitlist_count,
  case
    when j.slots_filled >= j.slots then 'filled'
    when j.status != 'active'       then 'closed'
    when count(a.id) filter (where a.is_waitlist = false
         and a.status not in ('withdrawn','rejected'))
         >= coalesce(j.slots_max_apps, j.slots * j.app_buffer_mult) then 'waitlist_only'
    else 'open'
  end                                           as application_status
from jobs j
left join applications a on a.job_id = j.id
left join job_waitlist w on w.job_id = j.id
group by j.id, j.title, j.slots, j.slots_filled,
         j.slots_max_apps, j.app_buffer_mult, j.status;

-- ── RLS FOR NEW TABLES ────────────────────────────────────────
alter table job_waitlist       enable row level security;
alter table platform_settings  enable row level security;

-- Waitlist: worker sees own, employer sees for their jobs
create policy "waitlist_worker" on job_waitlist
  for all using (
    worker_id in (select id from workers where profile_id = auth.uid())
  );

create policy "waitlist_employer" on job_waitlist
  for select using (
    job_id in (select id from jobs where employer_id = auth.uid())
  );

-- Platform settings: public read (prices shown to all), admin write only
create policy "settings_read" on platform_settings
  for select using (true);

create policy "settings_write" on platform_settings
  for all using (
    auth.uid() in (select id from profiles where role = 'admin')
  );

-- ── GRANT UPDATE LOCATION TO AUTHENTICATED USERS ─────────────
grant execute on function update_worker_location to authenticated;
grant execute on function check_application_eligibility to authenticated, anon;
grant execute on function search_workers_nearby to authenticated, anon;
grant execute on function search_jobs_nearby to authenticated, anon;

-- ════════════════════════════════════════════════════════════════
-- END OF SCHEMA PATCH v2
-- Summary of changes:
-- workers: +latitude, +longitude, +location(geography), +available_now
-- jobs:    +latitude, +longitude, +job_location(geography), +slots_filled
--          +urgent, +app_buffer_mult
-- new:     job_waitlist, platform_settings tables
-- new:     search_workers_nearby(), search_jobs_nearby() functions
-- new:     check_application_eligibility() function
-- new:     fill_job_slot() function
-- new:     job_application_status view
-- triggers: auto-fill slots, auto-close job, expire available_now
-- ════════════════════════════════════════════════════════════════
