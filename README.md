# ACR: Antigravity Comic Reader 🚀📚

**ACR (Antigravity Comic Reader)** is a premium, AI-enhanced comic reader for iOS, specifically designed as a client for **Komga** servers. It combines a modern "Neon" aesthetic with powerful artificial intelligence features to provide the ultimate digital comic experience.

---

## ✨ Key Features

### 🤖 AI-Powered Intelligence (Powered by Google Gemini)
*   **AI Translation**: Real-time optical character recognition (OCR) and translation of speech balloons. Read foreign comics in your native language instantly!
*   **Story Recap**: Can't remember what happened in the previous issue? ACR uses AI to generate concise story recaps based on your series and volume metadata.
*   **Persistence**: Translated balloons are cached locally for instant re-reading without consuming API quota.

### 🎨 Modern "Neon" UI
*   **Collectible Box View**: Folders and series are presented as elegant collectible boxes with lid-style lids and handle cutouts.
*   **Dynamic Backgrounds**: Immersive blurred cover art backgrounds that adapt to what you are currently viewing.
*   **Hero Sections**: Beautiful detail views for books with large high-resolution covers and extracted metadata.

### 📖 Professional Reader
*   **True Fullscreen**: Zero distractions—system bars are completely hidden during reading.
*   **Pinch-to-Zoom**: Native gesture support for exploring every detail of the artwork.
*   **Page Navigation**: Smooth thumbnail slider and quick navigation arrows.
*   **Sharing**: Integrated iOS Share Sheet to share your favorite panels with friends.

### 📂 Library Management
*   **Offline Mode**: Download books and series to your local storage for reading anywhere.
*   **Metadata Mastery**: Full support for `ComicInfo.xml` parsing, showing writers, pencillers, issue numbers, and summaries.
*   **Smart Refresh**: Automatically detects new downloads and updates your local library.

---

## 🔒 Security & Privacy

ACR is designed with a **"Zero-Leak"** security model:
*   **No Hardcoded Secrets**: All sensitive data (Komga credentials, Gemini/OpenAI API keys) are removed from the source code.
*   **Local Storage only**: Credentials are saved exclusively on your device using `@AppStorage` (Encrypted UserDefaults).
*   **Privacy-First**: Your data never leaves your device and is never committed to Git repositories.

---

## 🛠 Installation & Setup

1.  **Clone the repository**:
    ```bash
    git clone https://github.com/robgola/AntigravityComicsReader.git
    ```
2.  **Install Dependencies**:
    Requires CocoaPods for specialized image processing (OpenCV).
    ```bash
    pod install
    ```
3.  **Open in Xcode**: Use the `.xcworkspace` file.
4.  **Connect to Komga**:
    *   Navigate to the **Options** tab.
    *   Tap **EDIT** to enter your server address, port, and credentials.
    *   Paste your **Google Gemini API Key** for AI features.
    *   Tap **SAVE**.

---

## 📄 License

This project is specialized for the community. Please refer to developers for contribution guidelines.

---

*Enjoy your reading with ACR!*
