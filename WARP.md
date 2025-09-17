# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

Project overview
- Stack: Flutter (Dart 3.9), Riverpod, GoRouter, Firebase (Core/Auth/Firestore/Storage/Functions), Hive (local storage)
- Targets: Web, Android, iOS
- Backend: Firebase Cloud Functions (TypeScript, Node 20) under functions/
- Infra: Firebase config and rules under infra/ and firebase.json

Common commands
Flutter app
- Install deps: flutter pub get
- Run (web): flutter run -d chrome
- Run (Android): flutter run -d android
- Run (iOS): flutter run -d ios
- Analyze: flutter analyze
- Format: dart format .
- Build (web): flutter build web --release
- Build (Android APK): flutter build apk --release
- Clean: flutter clean

Code generation (freezed/json_serializable)
- One-time build: dart run build_runner build --delete-conflicting-outputs
- Watch on changes: dart run build_runner watch --delete-conflicting-outputs

Tests
- All tests: flutter test
- Single file: flutter test test/path_to_test.dart
- Filter by test name: flutter test --name "pattern"

Cloud Functions (TypeScript, Node 20)
- Install deps: cd functions && npm install
- Build: npm run build
- Emulate (Functions only): npm run serve
- Deploy Functions: npm run deploy

Firebase infra and hosting
- Deploy Firestore/Storage rules: firebase deploy --only storage,firestore:rules
- Build web and deploy hosting: flutter build web --release && firebase deploy --only hosting

Environment and emulators
- App uses .env for web FirebaseOptions and function settings. Copy .env.template to .env and fill values when targeting web builds.
- To point the Flutter app at local callable Functions emulator, set in .env:
  - FIREBASE_FUNCTIONS_EMULATOR_HOST=localhost
  - FIREBASE_FUNCTIONS_EMULATOR_PORT=5001
- Default Functions region is us-central1 (override with FIREBASE_FUNCTIONS_REGION in .env if needed).

High-level architecture
App bootstrap and configuration
- Entry: lib/main.dart
  - Loads dotenv (.env) for web FirebaseOptions; initializes Firebase (web uses env options, native uses platform files); enables Firestore offline persistence.
  - Initializes Hive (local DB) and Awesome Notifications channel (for download progress notifications).
  - MessagingService.init() is currently a no-op (push notifications disabled at runtime).
  - Sets up Riverpod providers and launches MaterialApp.router with GoRouter from routerProvider.

Navigation, state, theming
- Routing: lib/src/core/router/app_router.dart (GoRouter)
- State: Riverpod across features; shared preferences injected via providers
- Theming: lib/src/core/theme/* (AppTheme, ThemeController)

Data and domain modeling
- Firestore access and query helpers: lib/src/data/firestore/*
- Domain models use freezed/json_serializable (e.g., features/auth/domain, features/projects/domain). Run build_runner after changing *.dart model definitions.

Storage and file handling
- StorageService (lib/src/services/storage_service.dart) centralizes Firebase Storage uploads with content-type inference and customMetadata.uploaderId (for server-side rules). On web, custom metadata is minimized to avoid CORS preflight.
- DraftMediaStore (lib/src/services/draft_media_store.dart) persists picked media in Hive for offline drafts; supports XFile and PlatformFile sources with size/type guards.
- Utility image compression in lib/src/utils/image_utils.dart.
- Storage bucket resolution respects .env FIREBASE_STORAGE_BUCKET via storageForCurrentApp() and falls back to Firebase app options.

Cloud Functions integration
- FunctionsService (lib/src/services/functions_service.dart) wraps callable functions such as:
  - exportProjectZip(projectId): Generates Storage zip of a project’s metadata, updates, and files, returning a signed URL.
  - setUserClaims(email, role, blockId?): Assigns Firebase Auth custom claims and writes users/{uid}.
  - adminCreateUser/adminBulkCreateUsers: Admin user management; writes users docs and sets claims.
  - adminDeleteUser/adminBulkDeleteUsers: Deletes Auth users and cascades Firestore user/project data.
  - seedTestUsers, bootstrapDevAdmin, migrateDraftStatus, revokeUserTokens.
- Emulator support: FunctionsService reads FIREBASE_FUNCTIONS_EMULATOR_HOST/PORT from .env and directs calls to the emulator when set.

Firebase infra
- firebase.json maps rules to infra/firestore.rules and infra/storage.rules and hosts web from build/web with SPA rewrites and cache headers.
- .firebaserc sets the default project (nirmad-app). Change via Firebase CLI context when needed.
- Note: The current rules in infra/* are permissive (allow read/write for authenticated users). Tighten before production if stricter access is required.

Feature map (big picture)
- src/features/auth: login/onboarding, Auth repository, AppUser model (freezed)
- src/features/projects: project CRUD, updates, domain models (freezed), repositories, editors
- src/features/dashboard: nodal dashboards (charts via fl_chart), filters, and project snapshots
- src/features/admin: dev/prod admin UIs (user and claims management, utilities)
- src/shared: reusable widgets, download helpers, file helpers, navigation guards, blocks data
- src/core: bootstrap, caching, logging, prefs, theme, i18n, widgets (offline monitor)

Notes and gotchas
- Web service worker: If enabling push notifications on web later, ensure web/firebase-messaging-sw.js is served from the site root. Currently, MessagingService is a no-op, so pushes are effectively disabled.
- Storage metadata: For uploads to pass Storage rules that validate uploaderId, ensure FirebaseAuth.currentUser is available; on web the client may omit custom metadata to reduce CORS complexity.
- Bucket naming: Do not coerce bucket hostnames; the code respects whatever bucket is configured via env or FirebaseOptions.
- When changing freezed or json_serializable models, re-run build_runner to regenerate *.g.dart/*.freezed.dart files.

Project directives and context (read before making changes)
- Canonical docs:
  - .project_context/brief_context.md — Core architecture & development principles
  - .project_context/rules.md — Repo standards, coding/linting, CI, secrets policy
  - .project_context/architecture_plan.md — Modularization & DAO/caching plan (incremental; no runtime changes by itself)
  - .project_context/prd.md — Product requirements, roles, and flows
  - infra/uiux-guidelines.md — UI/UX principles (spacing, tokens, skeletons)

- Non-negotiable mandates (summary):
  - State: Riverpod only; avoid ad-hoc/global state beyond providers.
  - Layout & responsiveness: 4px spacing grid; wrap screens in SafeArea; prevent overflows using Wrap/Flexible/Expanded/FittedBox; prefer adaptive constructors where useful.
  - Performance: prefer const; class-based widgets over functions; lazy-load lists/data; compress assets; use provider.select to narrow rebuilds.
  - Errors & logging: robust try/catch for I/O; user-friendly messages; structured logs via logger/AppLogger; logs disabled in release builds.
  - Tooling: use gap for spacing; adopt vetted packages. Do not introduce fast_ui_kit unless explicitly requested.

- RBAC and claims:
  - Current implementation uses a single auth claim blockId for sub_nodal scoping. Treat blockId (singular) as the source of truth. Do not migrate to blocks[] without explicit instruction.
  - Server and client enforce permissions for exports and admin operations (see functions/src/index.ts and FunctionsService).

- Notifications:
  - No FCM triggers. Client MessagingService is a no-op. Do not enable push without direction.

- Navigation & theming:
  - Unified sidebar navigation across screen sizes; logout only in sidebar footer.
  - Typography via Google Fonts (Montserrat). English-only UI; forms may include Hindi hints.

- Storage & uploads:
  - Enforce content types and size limits; include customMetadata.uploaderId on non-web uploads; avoid custom metadata on web to minimize CORS preflight.
  - Use lib/src/utils/firebase_storage_bucket.dart storageForCurrentApp(); do not normalize/alter bucket hostnames.

- Firebase integration:
  - Web uses .env FirebaseOptions; native uses platform configs. FunctionsService respects FIREBASE_FUNCTIONS_EMULATOR_HOST/PORT and FIREBASE_FUNCTIONS_REGION.

- Architecture pathfinders:
  - Thin Firebase facade: lib/src/utils/firebase/firebase_client.dart (incremental abstraction of direct SDK usage).
  - Follow .project_context/architecture_plan.md for DAO/caching refactors in phases; maintain zero-breakage.

- Production safety:
  - infra/* rules in this repo are permissive for development (authenticated read/write). Tighten only with explicit instruction and after validating all flows.

Sources consulted
- README.md (setup, functions, notifications, and web run guidance)
- infra/README.md (rules intent), firebase.json/.firebaserc
- functions/src/index.ts and FunctionsService for callable API surface
- analysis_options.yaml and pubspec.yaml for linting and codegen configuration
