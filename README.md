# SHINGA — Rwanda's National Work Platform

> Connecting every type of worker with every type of employer across all 30 districts of Rwanda.

Built by **Bestie Companies Ltd** · [shinga.rw](https://shinga.rw)

---

## Platform Overview

SHINGA is Rwanda's full-spectrum labour marketplace — from daily casual work to permanent careers. Free to browse, pay only when you act.

### Business Model
| Action | Fee |
|---|---|
| Post a job (daily) | RWF 2,000 |
| Post a job (weekly) | RWF 4,000 |
| Post a job (monthly/contract/permanent) | RWF 8,000 |
| Post a job (bulk hire 10+) | RWF 15,000 |
| Apply to a job | RWF 500 |
| Contact a worker | RWF 1,500 |
| Get SHINGA Verified | RWF 10,000/year |

---

## Repository Structure

```
shinga-platform/
├── public/                  # All frontend pages
│   ├── shinga.html          # Main public platform
│   ├── shinga-worker.html   # Worker dashboard
│   ├── shinga-employer.html # Employer dashboard
│   ├── shinga-admin.html    # Admin dashboard
│   ├── shinga-worker-profile.html  # Public worker profile
│   └── bestie.html          # Bestie Companies Ltd website
│
├── docs/                    # Implementation guides & schema
│   ├── shinga-auth.html     # Auth system + Next.js code
│   ├── shinga-data-layer.html # API routes + SWR hooks
│   ├── shinga-payments.html # MoMo + Flutterwave integration
│   ├── shinga-sms.html      # Africa's Talking SMS guide
│   ├── shinga-schema.sql    # Supabase schema v1
│   └── shinga-schema-v2.sql # Schema patch (GPS + slots)
│
└── README.md
```

---

## Key Features

- **7 job types** — Daily, Weekly, Monthly, Contract, Permanent, Per Task, Bulk Hire
- **Slot-based applications** — Workers never pay into a filled position. Progress bars show slots live.
- **Waitlist system** — Queue full? Join free. SMS notified when slot opens.
- **GPS Nearby Search** — PostGIS radius search. Find workers within 1–20km. Available Now filter.
- **Inline auth** — OTP via phone. Account created in 60 seconds inside any action flow.
- **Available Now** — Workers toggle live availability. Auto-expires after 8 hours.
- **MoMo payments** — MTN MoMo + Airtel Money via Flutterwave.
- **SMS notifications** — Africa's Talking. 9 events in Kinyarwanda + English.
- **SHINGA Verified badge** — Annual ID verification. Verified workers hired 3× faster.

---

## Tech Stack (Production)

| Layer | Technology |
|---|---|
| Frontend | Next.js 14 (App Router) |
| Database | Supabase (Postgres + PostGIS + RLS) |
| Auth | Supabase Auth (Phone OTP) |
| Payments | Flutterwave + MTN MoMo Direct |
| SMS | Africa's Talking |
| Hosting | Vercel |
| Domain | shinga.rw (AOS Rwanda) |

---

## Deployment Stages

- [x] Platform UI built
- [x] Worker dashboard built
- [x] Employer dashboard built
- [x] Admin dashboard built
- [x] Auth system built
- [x] Payment integration written
- [x] SMS integration written
- [x] Database schema written (v1 + v2)
- [ ] Domain registered (shinga.rw)
- [ ] Supabase project created
- [ ] Next.js project scaffolded
- [ ] API keys obtained (Flutterwave, Africa's Talking)
- [ ] Deployed to Vercel
- [ ] Go live

---

## Company

**Bestie Companies Ltd**
An umbrella technology company building Rwanda's digital infrastructure.
Each product is designed to eventually spin off as a standalone company.

Products: SHINGA · Bestie Research · Bestie Books · RADTS · Inzulink

---

*© 2025 Bestie Companies Ltd · Rwanda*
