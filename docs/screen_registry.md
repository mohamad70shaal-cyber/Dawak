# Dawak — Screen Registry

Every screen in the prompt appears here. **Type**: `R` own route · `S` section/widget inside a parent route · `A` action (dialog / sheet / button) · `D` deferred (documented, not built).

**Machine-readable rule:** the *Route* column holds routes in backticks. `test/routing/route_audit_test.dart` parses this file and fails if (a) a registered `R` route has no `GetPage` in `AppPages`, (b) a `GetPage` has no row here, or (c) an `AppRoutes` constant is unused. Keep it in sync.

**Access:** `Pub` no auth · `Guest` unauthenticated only · `Cust` customer · `Pharm` approved pharmacy member · `Pharm*` pharmacist in any application state · `Admin` active admin.

**State rule (all `R` screens):** loading, error-with-retry and (for lists) empty states via the shared `AsyncStateView`; forms add inline validation, submitting and failure states. Success is shown only after the server confirms.

**Tests legend:** `R` route/guard test · `W` widget test (states) · `U` controller unit test · `Fn` workflow test (see `navigation_matrix.md`) · `DB` SQL test (`supabase/tests`).

**Implementation status** is tracked in `progress.md`, not here.

## Shared / shell

| ID | Screen | Route | Access | Controller | Entry → Exit | Type | Tests |
|---|---|---|---|---|---|---|---|
| X-01 | Customer shell (4 tabs, IndexedStack) | `/customer/home` `/customer/search` `/customer/orders` `/customer/profile` (same shell, initial tab differs) | Cust | CustomerShellController | login / splash / deep link → tab roots; back on a root exits app | R | R,W,F1 |
| X-02 | Pharmacist shell (5 tabs: Dashboard, POS, Orders, Products, Settings) | `/pharmacist/dashboard` `/pharmacist/pos` `/pharmacist/orders` `/pharmacist/products` `/pharmacist/settings` | Pharm | PharmacistShellController | login → tab roots | R | R,W,F2 |
| X-03 | Access denied | `/access-denied` | Pub | — | guard redirect → role home | R | R,W |
| X-04 | Not found | `/not-found` | Pub | — | unknown route → role home | R | R |
| X-05 | Account suspended | `/account-suspended` | Pub | AuthController | guard (suspended profile) → sign out | R | R,W,F5 |

## Customer — A. Onboarding and authentication

| ID | Screen | Route | Access | Controller | Data | Entry → Exit | Type | Tests |
|---|---|---|---|---|---|---|---|---|
| C-01 | Splash | `/splash` | Pub | SplashController | AuthRepository.restoreSession, ProfileRepository.me | app start → `/onboarding` (first run) · `/welcome` · role home · status screen | R | R,W,F5 |
| C-02 | Intro / onboarding | `/onboarding` | Pub | OnboardingController | local prefs | splash → `/welcome` | R | R,W |
| C-03 | Welcome | `/welcome` | Guest | — | — | → `/login` · `/register` · `/pharmacist/login` | R | R,W |
| C-04 | Customer login | `/login` | Guest | AuthController | AuthRepository.signIn | → `/customer/home`; wrong role → sign-out + error | R | R,W,U,F5 |
| C-05 | Customer registration | `/register` | Guest | AuthController | AuthRepository.signUp | → `/verify-email` (if confirmation on) or `/customer/home` | R | R,W,U |
| C-06 | Password reset | `/password-reset` | Guest | AuthController | AuthRepository.resetPassword | → `/login` | R | R,W,U |
| C-07 | Verification (email) | `/verify-email` | Guest | AuthController | AuthRepository.resendConfirmation | register → `/login` | R | R,W |
| C-08 | Auth loading / error states | — | — | AuthController | — | inside C-04…C-07 | S | W |

## Customer — B. Main experience

| ID | Screen | Route | Access | Controller | Data (repo → RPC/table) | Entry → Exit | Type | Tests |
|---|---|---|---|---|---|---|---|---|
| C-09 | Home | `/customer/home` | Cust | HomeController | MedicineRepository (categories), OrderRepository (recent) | → search, category results, order details | R | R,W,F1 |
| C-10 | Medicine search | `/customer/search` | Cust | MedicineSearchController | MedicineRepository → `search_medicines` | → results | R | R,W,U,F1 |
| C-11 | Search results | `/customer/search/results` | Cust | MedicineSearchController | `search_medicines` (paginated) | → details; back → search | R | R,W,U,F1 |
| C-12 | Search filters | `/customer/search/filters` | Cust | MedicineSearchController | categories, dosage forms | results → filters → results | R | R,W |
| C-13 | Medicine details (+ "ask nearby pharmacies") | `/customer/medicine/:id` | Cust | MedicineDetailsController | MedicineRepository (medicines) | → pharmacy results · ask nearby | R | R,W,F1 |
| C-14 | Pharmacies that confirmed the medicine (nearest first when located; price, confirmed when) | `/customer/medicine/:id/pharmacies` | Cust | MedicineDetailsController | `get_medicine_pharmacies` + LocationService | → pharmacy details · ask nearby | R | R,W,U,F1 |
| C-15 | Pharmacy details | `/customer/pharmacy/:id` | Cust | PharmacyDetailsController | `get_public_pharmacy`, `get_public_pharmacy_products` | → cart, contact | R | R,W,F1 |
| C-16 | Pharmacy contact | `/customer/pharmacy/:id/contact` | Cust | PharmacyDetailsController | `get_public_pharmacy` | back → details | R | R,W |
| C-17 | Cart (single pharmacy) | `/customer/cart` | Cust | CartController | local state; revalidated server-side | → review | R | R,W,U,F1 |
| C-18 | Order review / confirmation | `/customer/checkout/review` | Cust | CheckoutController | OrderRepository → `create_order` | → result | R | R,W,U,F1,F6 |
| C-19 | Order submission result | `/customer/checkout/result` | Cust | CheckoutController | result of `create_order` | → order details · home | R | R,W,F1 |
| C-20 | Order details | `/customer/orders/:id` | Cust | OrderDetailsController | orders + order_items (RLS) | → tracking, cancel | R | R,W,F1,F3 |
| C-21 | My orders | `/customer/orders` | Cust | CustomerOrdersController | orders (RLS) | → details | R | R,W,F1 |
| C-22 | Order status tracking | `/customer/orders/:id/tracking` | Cust | OrderDetailsController | orders timestamps | back → details | R | R,W,F3 |
| C-23 | Cancel order | `/customer/orders/:id/cancel` | Cust | OrderDetailsController | `cancel_order` | → details (refreshed) | R | R,W,U,F3 |
| C-24 | Profile | `/customer/profile` | Cust | CustomerProfileController | ProfileRepository | → edit, help, legal, logout | R | R,W |
| C-25 | Edit profile | `/customer/profile/edit` | Cust | CustomerProfileController | profiles (column-limited update) | → profile (refreshed) | R | R,W,U |
| C-26 | Notification centre | `/customer/notifications` | Cust | NotificationsController | notifications (RLS) | → order details | R | R,W |
| C-27 | Help and report an issue | `/customer/help` | Cust | SupportController | `user_reports` insert | profile → help | R | R,W,U |
| C-29 | Ask the nearby pharmacies: live results (radius 1 → 3 → 5 → 10 km, "search further", close) | `/customer/requests/:id` | Cust | AvailabilityRequestController | AvailabilityRepository → `create_availability_request`, `get_availability_request`, `expand_…`, `close_…` | C-13 / C-14 / C-30 → pharmacy details · directions | R | R,W,U,F7,DB |
| C-30 | My availability requests (history) | `/customer/requests` | Cust | MyRequestsController | `list_my_availability_requests` | profile / home → C-29 | R | R,W,U |
| C-31 | Start a request (explanation once per app run, location permission, one request per medicine and spot) | — | Cust | MedicineDetailsController (`askNearby`) | LocationService → `create_availability_request` | dialog from C-13 / C-14 → C-29 | A | U,F7 |
| C-28 | Privacy policy / Terms | `/legal/privacy` `/legal/terms` | Pub | LegalController | bundled localized text | auth screens, profile | R | R,W |

## Pharmacist — A. Registration and setup

| ID | Screen | Route | Access | Controller | Data | Entry → Exit | Type | Tests |
|---|---|---|---|---|---|---|---|---|
| P-01 | Pharmacist login | `/pharmacist/login` | Guest | AuthController | signIn | → `/pharmacist/dashboard` or a status screen | R | R,W,F5 |
| P-02 | Pharmacist registration | `/pharmacist/register` | Guest | AuthController | signUp | → `/pharmacist/pharmacy/register` | R | R,W,U |
| P-03 | Pharmacy registration (wizard host, licence upload, review, submit) | `/pharmacist/pharmacy/register` | Pharm* | PharmacyRegistrationController | StorageRepository, `register_pharmacy` | → P-04 → P-05 → P-06 → review → `/pharmacist/status/pending` | R | R,W,U,F4 |
| P-04 | Pharmacy information form | `/pharmacist/pharmacy/register/info` | Pharm* | PharmacyRegistrationController | local → submit | → P-05 | R | R,W,U |
| P-05 | Address, contact details and shop location | `/pharmacist/pharmacy/register/address` | Pharm* | PharmacyRegistrationController | LocationService / GeoParse → submit | → P-06 | R | R,W,U |
| P-06 | Operating hours | `/pharmacist/pharmacy/register/hours` | Pharm* | PharmacyRegistrationController | local → submit | → review | R | R,W,U |
| P-07 | Approval pending | `/pharmacist/status/pending` | Pharm* | PharmacyStatusController | PharmacyRepository.myPharmacy | → logout; auto-refresh → dashboard when approved | R | R,W,F4 |
| P-08 | Rejected (reason + resubmit) | `/pharmacist/status/rejected` | Pharm* | PharmacyStatusController | myPharmacy → `resubmit_pharmacy` | → wizard (prefilled) | R | R,W,F4 |
| P-09 | Suspended | `/pharmacist/status/suspended` | Pharm* | PharmacyStatusController | myPharmacy | → logout | R | R,W |

## Pharmacist — B. Dashboard

| ID | Screen | Route | Access | Controller | Data | Entry → Exit | Type | Tests |
|---|---|---|---|---|---|---|---|---|
| P-10 | Dashboard overview | `/pharmacist/dashboard` | Pharm | DashboardController | DashboardRepository → `pharmacy_dashboard` | → sales, orders, requests inbox, list | R | R,W,U,F2 |
| P-11 | Today's sales | — | Pharm | DashboardController | `pharmacy_dashboard` | card in P-10 | S | W |
| P-12 | This week's sales | — | Pharm | DashboardController | idem | card in P-10 | S | W |
| P-13 | Last 10 days' sales | — | Pharm | DashboardController | idem | card in P-10 | S | W |
| P-14 | This month's sales | — | Pharm | DashboardController | idem | card in P-10 | S | W |
| P-15 | Completed transaction count | — | Pharm | DashboardController | idem | card in P-10 | S | W |
| P-16 | Sales trend chart | — | Pharm | DashboardController | idem (daily series) | chart in P-10 | S | W |
| P-17 | Best-selling products | — | Pharm | DashboardController | idem | list in P-10 | S | W |
| P-18 | List needs confirming (available items not confirmed for a week) + "confirm all" | — | Pharm | DashboardController | idem + `confirm_listing` | card in P-10 → P-21 (filter: stale) | S | W,U |
| P-19 | Recent orders | — | Pharm | DashboardController | idem | list in P-10 → P-55/P-56 | S | W |
| P-20 | Date-range filters | — | Pharm | DashboardController | `pharmacy_dashboard(from,to)` | chips in P-10 | S | W,U |

## Pharmacist — C. Product management

| ID | Screen | Route | Access | Controller | Data | Entry → Exit | Type | Tests |
|---|---|---|---|---|---|---|---|---|
| P-21 | Product catalogue | `/pharmacist/products` | Pharm | ProductsController | ListingRepository (pharmacy_products RLS) | → details, add | R | R,W,U,F2 |
| P-22 | Search products | — | Pharm | ProductsController | client filter over loaded page + server query | field in P-21 | S | W,U |
| P-23 | Category filters | — | Pharm | ProductsController | medicine_categories | chips in P-21 | S | W |
| P-24 | Product details (price, available, confirmed when) | `/pharmacist/products/:id` | Pharm | ProductDetailsController | pharmacy_products + medicines | → edit | R | R,W,F2 |
| P-25 | Add product from shared catalogue | `/pharmacist/products/add` | Pharm | ProductAddController | medicines (approved) → `add_pharmacy_product` | → P-24 | R | R,W,U,F2 |
| P-26 | Propose new medicine (authorised workflow) | `/pharmacist/products/propose` | Pharm | MedicineProposalController | `propose_medicine` | → P-25 (dedupe returns existing) | R | R,W,U |
| P-27 | Edit price / availability | `/pharmacist/products/:id/edit` | Pharm | ProductEditController | `update_pharmacy_product` | → P-24 | R | R,W,U,F2 |
| P-28 | Update price | — | Pharm | ProductEditController | `update_pharmacy_product` | field/dialog in P-24/P-27 | A | U,F2 |
| P-29 | Import list from Excel / CSV (read, name matching + review, save) | `/pharmacist/products/import` | Pharm | ProductImportController | ImportParser (local) → `match_medicine_names` → `bulk_upsert_pharmacy_products` | P-21 → P-21 | R | R,W,U,F2,DB |
| P-30 | Confirm the whole list ("my list is correct today") | — | Pharm | ProductsController | `confirm_listing` | button in P-21 / card P-18 | A | U,DB |
| P-31 | Mark available / unavailable | — | Pharm | ProductDetailsController | `update_pharmacy_product(is_available)` | switch in P-24 / P-21 | A | U,F2 |
| P-32 | Requests inbox (customers asking about a medicine nearby) | `/pharmacist/requests` | Pharm | AvailabilityInboxController | `list_pharmacy_availability_requests`, `count_pharmacy_availability_requests` | badge in P-10 / notification → P-33 | R | R,W,U,F7 |
| P-33 | Answer a request: available (price pre-filled from the list) / unavailable | `/pharmacist/requests/:id` | Pharm | AvailabilityAnswerController | `answer_availability_request` | P-32 → P-32 | R | R,W,U,F7,DB |

## Pharmacist — D. Point of sale

| ID | Screen | Route | Access | Controller | Data | Entry → Exit | Type | Tests |
|---|---|---|---|---|---|---|---|---|
| P-34 | POS home | `/pharmacist/pos` | Pharm | PosController | SalesRepository | → checkout | R | R,W,U,F2 |
| P-35 | Product search | — | Pharm | PosController | pharmacy_products | field in P-34 | S | W,U |
| P-36 | Add / remove cart items | — | Pharm | PosController | local | P-34 | S | U |
| P-37 | Change quantity | — | Pharm | PosController | local (re-validated on server) | P-34 | S | U |
| P-38 | Apply discount | — | Pharm | PosController | validated in `create_pos_sale` | dialog (owner/manager only) | A | U,DB |
| P-39 | Subtotal / total preview | — | Pharm | PosController | local preview; server total is authoritative | P-34/P-41 | S | U |
| P-40 | Line validation (price and medicine only; no stock check) | — | Pharm | PosController | server `invalid_input` | P-34/P-41 | S | U,DB |
| P-41 | Confirm cash sale | `/pharmacist/pos/checkout` | Pharm | PosController | `create_pos_sale` (idempotency key) | → P-42 | R | R,W,U,F2,F6 |
| P-42 | Sale completed | `/pharmacist/pos/completed/:saleId` | Pharm | PosController | `get_sale` | → P-43 · new sale | R | R,W,F2 |
| P-43 | Receipt details | `/pharmacist/sales/:id` | Pharm | SalesController | `get_sale` | from P-42/P-48/P-62 | R | R,W,F2 |
| P-44 | PDF receipt | — | Pharm | ReceiptService | `get_sale` → pdf | button in P-43 | A | U |
| P-45 | Print / share receipt | — | Pharm | ReceiptService | pdf → printing/share | button in P-43 | A | U |
| P-46 | Start new sale | — | Pharm | PosController | clears cart | button in P-42 | A | U,F2 |
| P-47 | Transaction failure handling | — | Pharm | PosController | error mapping | P-34/P-41 | S | W,U,F6 |

## Pharmacist — E. Sales history

| ID | Screen | Route | Access | Controller | Data | Entry → Exit | Type | Tests |
|---|---|---|---|---|---|---|---|---|
| P-48 | Sales history | `/pharmacist/sales` | Pharm | SalesController | sales (RLS) paginated | → P-43 | R | R,W,U,F2 |
| P-49 | Search by invoice number | — | Pharm | SalesController | sales filter | field in P-48 | S | U |
| P-50 | Filter by date | — | Pharm | SalesController | sales filter | chips/picker in P-48 | S | U |
| P-51 | Sale details | `/pharmacist/sales/:id` | Pharm | SalesController | `get_sale` | = P-43 | R | R,W |
| P-52 | Receipt reprint / share | — | Pharm | ReceiptService | pdf | button in P-43 | A | U |
| P-53 | Return / refund workflow | — | — | — | — | **Deferred** (requirements §5) | D | — |
| P-54 | Audit record for discounts | — | Pharm | SalesController | audit_logs + discount shown on sale | covered by P-43 | S | W,DB |

## Pharmacist — F. Order management

| ID | Screen | Route | Access | Controller | Data | Entry → Exit | Type | Tests |
|---|---|---|---|---|---|---|---|---|
| P-55 | New reservations (tabs: new / accepted / ready / history / expired) | `/pharmacist/orders` | Pharm | PharmacistOrdersController | orders (RLS), `expire_reservations` on open | → P-56 | R | R,W,U,F3 |
| P-56 | Order details | `/pharmacist/orders/:id` | Pharm | PharmacistOrderDetailsController | orders, order_items | → handover | R | R,W,F3 |
| P-57 | Accept order | — | Pharm | PharmacistOrderDetailsController | `accept_order` | button in P-56 | A | U,F3,DB |
| P-58 | Reject with reason | — | Pharm | PharmacistOrderDetailsController | `reject_order` | dialog in P-56 | A | U,F3,DB |
| P-59 | Mark ready for pickup | — | Pharm | PharmacistOrderDetailsController | `mark_order_ready` | button in P-56 | A | U,F3,DB |
| P-60 | Find order by reference | `/pharmacist/orders/find` | Pharm | PharmacistOrdersController | `find_order_by_ref` | → P-56 | R | R,W,U,F3 |
| P-61 | Verify order before handover | `/pharmacist/orders/:id/handover` | Pharm | PharmacistOrderDetailsController | reference confirmation field | P-56 → P-62 | R | R,W,F3 |
| P-62 | Complete handover and sale | — | Pharm | PharmacistOrderDetailsController | `complete_order` | button in P-61 → `/pharmacist/sales/:id` | A | U,F3,DB |
| P-63 | Cancel accepted reservation | — | Pharm | PharmacistOrderDetailsController | `pharmacy_cancel_order` | dialog in P-56 | A | U,F3,DB |
| P-64 | Expired reservations (+ reactivate) | — | Pharm | PharmacistOrdersController | `expire_reservations`, `reactivate_order` | tab in P-55 | S | W,U,F3,DB |
| P-65 | Reservation expiry display | — | Pharm | PharmacistOrderDetailsController | `reservation_expires_at` | widget in P-55/P-56 | S | W |
| P-66 | Promise status ("held until …") | — | Pharm | PharmacistOrderDetailsController | `reservation_expires_at` | widget in P-56 | S | W |

## Pharmacist — G. Settings

| ID | Screen | Route | Access | Controller | Data | Entry → Exit | Type | Tests |
|---|---|---|---|---|---|---|---|---|
| P-S0 | Settings hub | `/pharmacist/settings` | Pharm | PharmacySettingsController | — | → P-67…P-72, P-74, sales | R | R,W |
| P-67 | Pharmacy profile | `/pharmacist/settings/profile` | Pharm | PharmacySettingsController | `update_my_pharmacy` | → hub | R | R,W,U |
| P-68 | Address and phone | `/pharmacist/settings/contact` | Pharm | PharmacySettingsController | `update_my_pharmacy` | → hub | R | R,W,U |
| P-69 | Operating hours | `/pharmacist/settings/hours` | Pharm | PharmacySettingsController | `update_my_pharmacy` | → hub | R | R,W,U |
| P-70 | Account and security | `/pharmacist/settings/security` | Pharm | PharmacySettingsController | AuthRepository.updatePassword | → hub | R | R,W,U |
| P-71 | Employee management | — | — | — | — | **Deferred** (requirements §5) | D | — |
| P-73 | Notification centre | `/pharmacist/notifications` | Pharm | NotificationsController | notifications (RLS) | bell in P-10 / P-55 → order details | R | R,W |
| P-74 | Pharmacy location (GPS or pasted map link / coordinates) | `/pharmacist/settings/location` | Pharm | PharmacySettingsController | LocationService, GeoParse → `update_my_pharmacy` | → hub | R | R,W,U |
| P-72 | Logout | — | Pharm | AuthController | signOut | hub → `/welcome` | A | U,F5 |

## Admin

| ID | Screen | Route | Access | Controller | Data | Entry → Exit | Type | Tests |
|---|---|---|---|---|---|---|---|---|
| A-01 | Admin login | `/admin/login` | Guest | AuthController | signIn + role check | → `/admin/dashboard` | R | R,W,F5 |
| A-02 | Dashboard and operational metrics | `/admin/dashboard` | Admin | AdminDashboardController | `admin_metrics` | → approvals, reports | R | R,W,F4 |
| A-03 | Pending pharmacy applications | `/admin/pharmacies/pending` | Admin | PharmacyApprovalsController | pharmacies (admin RLS) | → A-04 | R | R,W,F4 |
| A-04 | Application details | `/admin/pharmacies/:id` | Admin | PharmacyApprovalsController | pharmacies, owner profile, licence signed URL | → A-05 | R | R,W,F4 |
| A-05 | Approve / reject | — | Admin | PharmacyApprovalsController | `admin_review_pharmacy` | buttons in A-04 | A | U,F4,DB |
| A-06 | All pharmacies (suspend / reinstate) | `/admin/pharmacies` | Admin | PharmacyApprovalsController | pharmacies, `admin_review_pharmacy` | → A-04 | R | R,W,U,F4 |
| A-07 | Medicine catalogue management | `/admin/medicines` | Admin | MedicineCatalogController | medicines (admin RLS), `admin_review_medicine` | → A-08 | R | R,W,U |
| A-08 | Medicine editor / proposal review | `/admin/medicines/:id` (`/admin/medicines/new` for create) | Admin | MedicineCatalogController | medicines write | back → A-07 | R | R,W,U |
| A-09 | Category management | `/admin/categories` | Admin | CategoriesController | medicine_categories | — | R | R,W,U |
| A-10 | User reports | `/admin/reports` | Admin | ReportsController | user_reports | → A-11 | R | R,W |
| A-11 | Report review | `/admin/reports/:id` | Admin | ReportsController | `admin_resolve_report` | → A-10 | R | R,W,U |
| A-12 | Accounts | `/admin/users` | Admin | UsersController | profiles (non-customer), `admin_set_account_status` | — | R | R,W,U |
| A-13 | Audit log viewer | `/admin/audit-logs` | Admin | AuditLogsController | audit_logs (admin RLS) paginated | — | R | R,W |
| A-14 | Access denied | `/access-denied` | Pub | — | = X-03 | guard redirect | R | R |
| A-15 | Secure sign-out | — | Admin | AuthController | signOut | menu → `/welcome` | A | U,F5 |
| A-16 | Import medicines from Excel / CSV | `/admin/medicines/import` | Admin | AdminMedicineImportController | A-07 → A-07 | R | U |

## Coverage check

- Customer: C-01…C-31 → 31 rows (C-08 section, C-28 two routes; C-29 results, C-30 history, C-31 is the start dialog of the ask-nearby flow and has no route).
- Pharmacist: P-01…P-74 → 74 rows (P-53, P-71 deferred; P-73 notifications, P-74 shop location) plus P-S0.
- Admin: A-01…A-16.
- Extra: X-01…X-05.
