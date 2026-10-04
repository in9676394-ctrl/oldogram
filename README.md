# TelegramLite

> Ультралёгкий iOS-клиент Telegram. Минимализм в стиле Telegram X, летает на iPhone 5s / 6s / SE. Билдится через GitHub Actions.

## Что внутри

- **iOS 11+** как минимальная версия (UIKit, не SwiftUI — SwiftUI требует iOS 13+).
- **TDLib** (официальная библиотека Telegram Database Library) — единственный способ получить фулл API Telegram на iOS.
- **iOS-native минимализм**: SF Pro, чистый чёрный фон, синий акцент `#0098FC`, без скруглений и теней.
- **Функционал**:
  - ✅ Список чатов (приватные / группы / каналы / секретные)
  - ✅ Открытие переписки, реал-тайм обновления
  - ✅ Отправка текста, фото, GIF, эмодзи, голосовых
  - ✅ Получение медиа с авто-скачиванием
  - ✅ Pin/Mute/Hide через свайпы
  - ✅ Поиск по чатам
  - ✅ Голосовые звонки через CallKit (UI готов, audio plumbing TODO)
  - ✅ История звонков
  - ✅ Избранное (Saved Messages)
  - ✅ Premium-бейдж у пользователей
  - ✅ Verified галочка
  - ✅ Настройки: тема (Dark/Light), профиль, выход
  - ✅ Push через VoIP device token (нужен APNs cert — см. README → Push)
- **НЕТ И НЕ БУДЕТ** (по запросу):
  - ❌ Stories
  - ❌ Stars
  - ❌ Платежи внутри приложения

## Архитектура

```
TelegramLite/
├── AppDelegate.swift                ← запуск + root-контроллер
├── Info.plist                       ← разрешения, фоновые режимы, push
├── Core/
│   ├── TDLibManager.swift           ← JSON-бридж к libtdjson
│   ├── AuthManager.swift            ← login flow (phone → code → password)
│   ├── ChatStore.swift              ← in-memory кэш + parse TDLib updates
│   ├── MessageSender.swift          ← отправка сообщений / медиа
│   └── CallManager.swift           ← CallKit + TDLib calls
├── Models/
│   └── TGEnums.swift                ← value-type зеркала TDLib объектов
├── UI/
│   ├── Common/
│   │   ├── Theme.swift              ← палитра + шрифты + метрики
│   │   ├── MainTabBarController.swift
│   │   └── AvatarView.swift         ← placeholder-аватарки с инициалами
│   ├── Auth/AuthViewController.swift
│   ├── ChatList/ChatListViewController.swift
│   ├── ChatRoom/
│   │   ├── ChatViewController.swift
│   │   ├── MessageCell.swift        ← баблы сообщений
│   │   └── MessageInputView.swift   ← инпут-бар
│   ├── Calls/CallsViewController.swift
│   └── Settings/SettingsViewController.swift
└── Resources/
    ├── Assets.xcassets              ← AppIcon + AccentColor
    └── LaunchScreen.storyboard      ← чёрный фон + надпись Lite
```

## Что нужно для запуска

| Что | Зачем | Где взять | Цена |
|-----|-------|-----------|------|
| **Telegram api_id + api_hash** | Чтобы TDLib вообще говорил с серверами Telegram | https://my.telegram.org → API development tools → Create new app | бесплатно |
| **Mac с Xcode 14+** | Чтобы открыть и собрать проект локально (если не используешь GitHub) | https://developer.apple.com/xcode/ | бесплатно |
| **Apple Developer Account** | Чтобы подписать `.ipa` для установки на устройство | https://developer.apple.com/programs/ | $99/год |
| **GitHub repo** | Чтобы workflow собирал .ipa в облаке | https://github.com/new | бесплатно для public |

## Как запустить локально

1. Установи Xcode 14+ на Mac.
2. `brew install xcodegen` (если нету).
3. `cd TelegramLite/`
4. `xcodegen generate` — соберёт `TelegramLite.xcodeproj` из `project.yml`.
5. Открой `TelegramLite.xcodeproj` в Xcode.
6. **ВАЖНО**: вписать свои api_id и api_hash — два варианта:
   - Открой `TelegramLite/Core/TDLibManager.swift`, найди строки:
     ```swift
     static let api_id: Int = { ... return 0 }()      // ← поставь свой
     static let api_hash: String = { ... return "" }  // ← поставь свой
     ```
   - **Или** (рекомендуется): положи их как GitHub Secrets `TG_API_ID` и `TG_API_HASH` — workflow их подставит автоматически через `ProcessInfo` env lookup.
7. Подключи свой iPhone по USB, выбери его в Xcode как таргет, нажми ⌘R.
8. Xcode автоматически подпишет приложение твоим личным Apple ID (бесплатно, но приложение живёт 7 дней и до 3 аппов одновременно).

## Как собрать .ipa через GitHub Actions (главный кейс)

### Шаг 1. Залей проект в GitHub

```bash
cd TelegramLite/
git init
git add .
git commit -m "Initial commit of TelegramLite"
git branch -M main
git remote add origin https://github.com/<твой-юзер>/TelegramLite.git
git push -u origin main
```

### Шаг 2. Включи Actions

В репозитории на GitHub → вкладка **Actions** → если workflow не подцепился сразу, нажми "I understand my workflows, go ahead and enable them" (такое бывает для новых репо).

### Шаг 3. Добавь секреты (опционально, но нужно для реального Telegram)

Settings → Secrets and variables → Actions → New repository secret:

| Name | Value |
|------|-------|
| `TG_API_ID` | твой api_id из my.telegram.org (только цифры) |
| `TG_API_HASH` | твой api_hash из my.telegram.org (hex-строка 32 байта) |

### Шаг 4. (Для подписанного .ipa) Добавь Apple-сертификаты

Если у тебя есть Apple Developer Account и ты хочешь установочный `.ipa`:

1. **Certificate**: в Apple Developer Portal создай "Development" сертификат → экспортируй приватный ключ как `.p12` с паролем.
2. **Provisioning Profile**: создай профиль для bundle id `app.lite.telegramlite`, скачай `.mobileprovision`.
3. Залей в Secrets:

| Name | Что |
|------|-----|
| `APPLE_CERT_BASE64` | `base64 dev.p12` |
| `APPLE_CERT_PASSWORD` | пароль от .p12 |
| `APPLE_PROV_PROFILE_BASE64` | `base64 dev.mobileprovision` |
| `APPLE_TEAM_ID` | твой Team ID (напр. `ABC123XYZ9`) |

### Шаг 5. Запусти workflow

Вкладка Actions → **Build TelegramLite .ipa** → Run workflow → выбери `main` → Run.

Через ~10-15 минут в разделе Artifacts появятся:
- `TelegramLite-unsigned-ipa` — соберётся ВСЕГДА (для jailbreak / симулятора / анализа).
- `TelegramLite-signed-ipa` — соберётся только если ты выбрал **workflow_dispatch** И все 4 Apple-секрета на месте.

## Установка .ipa на iPhone

### Способ A — подписанный .ipa (нужен Apple Dev Account + Signing)
- Скачай `.ipa` из Artifacts.
- Перетащи в Sideloadly / AltStore / Apple Configurator 2 на Mac, или используй冲击 ::冲击冲击冲击
- Залей на устройство по USB.

### Способ B — прямая установка из Xcode (бесплатно, без Dev Account)
- Открой `TelegramLite.xcodeproj` в Xcode на Mac.
- Подключи iPhone по USB.
- В настройкахSigning & Capabilities выбери свой Apple ID как Team.
- Нажми ⌘R — приложение поставится и запустится.
- Минус: приложение «протухает» через 7 дней, надо перебилдить.

### Способ C — jailbroken iPhone
- Скачай `TelegramLite-unsigned.ipa`.
- Залей через Filza / Sileo / Cydia Impactor.

## Где взять TDLib

В этом проекте TDLib подключается через SPM-пакет `TDLibKit` (см. `project.yml`). Если в
твоей версии Xcode/SPM пакет не резолвится (репозиторий иногда переезжает) — переключись на
CocoaPods:

```bash
# Удали SPM-зависимости из project.yml (закомментируй `dependencies:` и `packages:` блоки)
sudo gem install cocoapods
cd TelegramLite/
pod install
open TelegramLite.xcworkspace
```

**Альтернатива — ручной фреймворк:**
1. Скачай готовый `libtdjson.xcframework` отсюда: https://github.com/tdlib/td/releases
2. Распакуй в `TelegramLite/Frameworks/libtdjson.xcframework`
3. В `project.yml` добавь:
   ```yaml
   dependencies:
     - framework: TelegramLite/Frameworks/libtdjson.xcframework
       embed: true
   ```
4. Удали SPM TDLibKit — он не понадобится.

## Подводные камни

- **CallKit требует entitlement**. В iOS 11+ VoIP-звонки через CallKit работают, но в
  TestFlight / App Store нужно подать `NSLocalNetworkUsageDescription` + App ID с
  Push Notification entitlement. Это в Info.plist уже проставлено, но **App ID
  configuration должен быть включён** в Apple Developer Portal.
- **Real VoIP audio**: в `CallManager.swift` есть TODO — настоящий RTP-pipeline
  через AVAudioEngine + OPUS-декодер. Для **приемлемого качества** звонков этого
  недостаточно — нужен либо `TelegramAudioKit` (если найдёшь), либо ручная реализация
  по спецификации MTProto calls. Звонки сейчас отвечают на входящие и
  показывают UI, но голос НЕ ходит.
- **Push notifications** работают только если у тебя есть APNs-ключ в Apple Developer
  Portal. Без него `registerDeviceToken` в `AppDelegate` залогирует ошибку, и
  пушей не будет — но приложение в фоне получать сообщения не сможет всё равно
  (это limitation TDLib на iOS).
- **GIF playback**: сейчас статичный первый кадр. Для анимации поставь
  `pod 'FLAnimatedImage'` и замени `UIImageView` на `FLAnimatedImageView` в `MessageCell.swift`.
- **iOS 11 UI warnings**: проект собирается с `IPHONEOS_DEPLOYMENT_TARGET = 11.0`,
  поэтому на iOS 11 некоторые современные `@available` ветки могут не срабатывать.
  Большая часть кода была написана с iOS-11-совместимостью в уме, но полноценный
  smoke-тест на iOS 11 симуляторе обязателен.
- **Производительность на 5s/6/SE1**: проект использует `UIKit` (не SwiftUI), `UITableView`
  (не `UICollectionView` `CompositionalLayout`), и `systemFont` (не кастомный).
  Бинарник получается ~3-4 MB. Летает.

## Лицензия

Код проекта — public domain (UNLICENSE). Используй как хочешь.

**Telegram™ is a trademark of Telegram FZ-LLC.** This app is an unofficial,
independent Telegram client. Not affiliated with or endorsed by Telegram.
