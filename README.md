# ci_makeup

A new Flutter project.

Run the browser version locally with `flutter run -d chrome`. To publish it,
run `flutter build web` and deploy the contents of `build/web`.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Supabase product catalog

The app reads the `products` table from Supabase for the Category page and
product search. The table must expose `id` (for ordering), `name`, `category`,
`price` (numeric), and `image_url` columns. `image_url` can be an app asset path
such as `assets/images/blush.jpg` or an HTTP(S) image URL. Make sure the
Supabase Row Level Security policies allow the app's publishable key to select
the product rows.
