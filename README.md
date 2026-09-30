# Chennapatanam

Construction CRM for a CEO: projects, timelines, daily progress, money and people.
Flutter (Android, iOS, web) + Firebase (Auth email/password, Firestore). No Cloud Functions yet.

## Run it

1. Firebase console for project `cptmn-dd372`:
   - Authentication → Sign-in method → enable **Email/Password**.
   - Firestore Database → create database (region `asia-south1`, production mode).
2. Deploy the security rules (CLI must be logged in to the account that owns the project):
   ```
   firebase login          # or: firebase login:add, then firebase login:use <email>
   firebase deploy --only firestore:rules,firestore:indexes
   ```
3. `flutter run -d chrome` (or an Android device).
4. First launch shows **Set up your company**. Setup code: `CPT-7Q4M-2XK9` (set in `firestore.rules`).
   That creates the first admin and default settings. The admin then adds the CEO and managers under **Users**.

## Structure

```
lib/core/        config (lists, custom fields, defaults), dynamic_form, data (tolerant JSON, audit),
                 router (role guards, responsive shell), theme, utils (money in paise, work-day keys), widgets
lib/features/    auth, users, profile, settings, home, projects (model + repository, no screens yet)
firestore.rules  roles read from users/{uid}; soft deletes only; audit stamps verified
```

## Conventions

- Money is integer **paise**. Dates for daily records are `YYYY-MM-DD` in IST (`WorkDay`).
- Lists, stages, categories and custom fields live in `config/*`. Items are archived, never deleted. Ids never change.
- Every write stamps `createdAt/By`, `updatedAt/By`, `schemaVersion`, and writes an `activity/` entry in the same batch.
- New users are created with a secondary Firebase app, so the admin stays signed in.
