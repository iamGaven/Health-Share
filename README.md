# HealthShare

Automatically syncs your FatSecret food diary to Google Health Connect.

---

## What It Does

- Connects to your FatSecret account via OAuth
- Syncs today's food entries to Google Health Connect
- Runs in the background on a configurable interval (minimum 15 minutes)
- Removes entries from Health Connect if you delete them from FatSecret
- Skips duplicates so nothing gets written twice
- Sends a notification when a background sync occurs

---

## Setup

### 1. Clone the repo
```bash
git clone https://github.com/iamGaven/Health-Share.git
cd Health-Share
```

### 2. Add your FatSecret API credentials
Create `assets/config/.env`:

FATSECRET_CONSUMER_KEY=your_key_here

FATSECRET_CONSUMER_SECRET=your_secret_here

### 3. Install dependencies
```bash
flutter pub get
```

### 4. Run the app
```bash
flutter run
```

---

## Requirements

- Android device with Google Health Connect installed
- FatSecret account
- FatSecret API credentials from [platform.fatsecret.com](https://platform.fatsecret.com)

