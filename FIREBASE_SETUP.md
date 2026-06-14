# Firebase Setup Guide for Khulasah

This guide explains how to set up Firebase for the Khulasah app.

## Prerequisites

- Node.js 18 or later
- Firebase CLI (`npm install -g firebase-tools`)
- FlutterFire CLI (`dart pub global activate flutterfire_cli`)
- A Firebase project

## Step 1: Firebase Login

```bash
firebase login
```

## Step 2: Initialize Firebase in Project

```bash
firebase init
```

Select:
- Functions (JavaScript)
- Use existing project (or create new)

## Step 3: Configure Flutter

```bash
flutterfire configure
```

This will:
- Create `lib/firebase_options.dart`
- Configure iOS and Android apps

## Step 4: Update main.dart

Add Firebase initialization:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const KhulasahApp());
}
```

## Step 5: Install Functions Dependencies

```bash
cd functions
npm install
```

## Step 6: Deploy Functions

```bash
firebase deploy --only functions
```

## Step 7: Add OpenAI API Key (When Ready)

```bash
# Set the API key securely
firebase functions:config:set openai.key="YOUR_OPENAI_API_KEY"

# Deploy again to apply
firebase deploy --only functions
```

## Local Development

### Run Functions Emulator

```bash
cd functions
npm run serve
```

The emulator runs at `http://localhost:5001`

### Use Emulator in Flutter

Uncomment this line in `firebase_functions_service.dart`:

```dart
_functions!.useFunctionsEmulator('localhost', 5001);
```

## Troubleshooting

### Firebase not initialized error

Make sure `flutterfire configure` was run and `firebase_options.dart` exists.

### Functions not deploying

Check Node.js version (must be 18+):
```bash
node --version
```

### OpenAI errors

Verify API key is set:
```bash
firebase functions:config:get
```

## Project Structure

```
khulasah_app/
├── lib/
│   ├── services/
│   │   ├── backend_service.dart         # Main service (tries Firebase first)
│   │   └── firebase_functions_service.dart  # Firebase integration
│   └── ...
├── functions/
│   ├── index.js                         # Functions entry point
│   ├── package.json                     # Node dependencies
│   └── src/
│       ├── generateResult.js            # Main AI function
│       ├── prompts.js                   # OpenAI prompts
│       └── validators.js                # Input validation
└── ...
```

## Security Notes

- **NEVER** put API keys in Flutter code
- **NEVER** commit `firebase_options.dart` with sensitive data
- Use Firebase Functions Config for secrets
- Enable App Check for production

## Next Steps

1. Complete Firebase setup
2. Test with dummy functions
3. Add OpenAI API key
4. Uncomment OpenAI code in `generateResult.js`
5. Deploy and test real AI generation
