-- ONE-TIME bootstrap of the first administrator. Run it by hand in the Supabase SQL editor (it runs as the
-- `postgres` role). There is deliberately no API or app screen for this: nobody can promote themselves,
-- because clients have no UPDATE privilege on profiles.role (enforced by triggers and tests).
--
-- 1. Sign up normally in the app with the admin's e-mail address (it creates a customer account).
-- 2. Replace the e-mail below and run the statement. Further admins are created the same way.
update public.profiles p
set role = 'admin'
from auth.users u
where u.id = p.id
  and u.email = 'admin@example.com';   -- <-- change me
-- Expect "UPDATE 1". The change is recorded nowhere automatically, so note it in your own ops log.
