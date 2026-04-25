# MacRemote — Пульт управления Mac с iPhone

Два приложения: iOS-пульт (iPhone) и macOS-сервер (Mac). Связь через Wi-Fi (Bonjour) и Bluetooth (MultipeerConnectivity).

## Возможности

### iOS-приложение (пульт)
- **Тачпад** — управление курсором, тап = клик, двойной тап = двойной клик, два пальца = правый клик, скролл двумя пальцами, long press = перетаскивание
- **Клавиатура** — ввод текста через системную клавиатуру, горячие клавиши (Cmd+C/V/X/Z, Cmd+S, Cmd+Tab, Esc и др.), стрелки, модификаторы
- **Медиа-пульт** — play/pause, prev/next, громкость, яркость, mute
- **Связь** — автообнаружение Mac в сети, авто-переподключение

### macOS-приложение (сервер)
- Живёт в меню баре (без иконки в Dock)
- Показывает количество подключённых устройств
- Принимает команды и управляет мышью/клавиатурой/медиа через CGEvent и IOKit

## Требования

- **Xcode 15+**
- **macOS 14+ (Sonoma)** для серверного приложения
- **iOS 17+** для iPhone
- **XcodeGen** (для генерации .xcodeproj) — [установка](#установка-xcodegen)

## Быстрый старт

### 1. Установка XcodeGen

```bash
brew install xcodegen
```

### 2. Генерация Xcode-проектов

```bash
# macOS-сервер
cd MacRemoteServer
xcodegen generate
cd ..

# iOS-приложение
cd MacRemote
xcodegen generate
cd ..
```

### 3. Открытие в Xcode

```bash
# Серверное приложение
open MacRemoteServer/MacRemoteServer.xcodeproj

# iOS-приложение
open MacRemote/MacRemote.xcodeproj
```

### 4. Настройка подписи (Signing)

В обоих проектах в Xcode:
1. Выбери цель (target) → вкладка **Signing & Capabilities**
2. Выбери свой **Team** (Apple ID / Developer Account)
3. Убедись, что **Automatically manage signing** включён

### 5. Сборка и запуск

#### macOS-сервер:
1. Открой `MacRemoteServer.xcodeproj`
2. Выбери target **MacRemoteServer**, destination **My Mac**
3. Нажми **⌘R** (Run)
4. При первом запуске macOS попросит дать **Accessibility** доступ:
   - Открой **Системные настройки → Конфиденциальность → Универсальный доступ**
   - Добавь **MacRemote Server** в список
5. В меню баре появится иконка антенны

#### iOS-приложение:
1. Открой `MacRemote.xcodeproj`
2. Подключи iPhone или выбери симулятор
3. Нажми **⌘R** (Run)
4. iPhone попросит доступ к локальной сети — разреши
5. Перейди на вкладку **Связь** — увидишь свой Mac в списке
6. Нажми на него для подключения

### Альтернатива без XcodeGen

Если не хочешь ставить XcodeGen:

1. Открой Xcode → **File → New Project**
2. Для сервера: выбери **macOS → App**, назови `MacRemoteServer`
3. Для iOS: выбери **iOS → App**, назови `MacRemote`
4. Удали сгенерированные файлы (ContentView.swift, App.swift)
5. Перетащи все `.swift` файлы из соответствующей папки в навигатор проекта
6. Добавь `Info.plist` в настройках target
7. Для сервера: **отключи App Sandbox** в Signing & Capabilities

## Архитектура

```
MacRemote/               ← iOS-приложение (пульт)
├── MacRemoteApp.swift
├── Views/
│   ├── ContentView.swift
│   ├── TouchpadView.swift
│   ├── KeyboardView.swift
│   ├── MediaControlView.swift
│   └── ConnectionView.swift
├── Networking/
│   ├── BonjourBrowser.swift
│   ├── MultipeerBrowser.swift
│   └── ConnectionManager.swift
├── Model/
│   └── RemoteCommand.swift
└── Info.plist

MacRemoteServer/         ← macOS-приложение (сервер)
├── MacRemoteServerApp.swift
├── Views/
│   └── StatusView.swift
├── Networking/
│   ├── BonjourServer.swift
│   ├── MultipeerServer.swift
│   └── ConnectionManager.swift
├── Input/
│   ├── MouseController.swift
│   ├── KeyboardController.swift
│   └── MediaController.swift
├── Model/
│   └── RemoteCommand.swift
└── Info.plist
```

## Протокол связи

Команды передаются как JSON, разделённый переводами строк:

```json
{"type":"mousemove","dx":5.2,"dy":-3.1}
{"type":"click","button":"left","count":1}
{"type":"scroll","dx":0,"dy":-10}
{"type":"keypress","text":"привет"}
{"type":"hotkey","modifiers":["cmd"],"key":"c"}
{"type":"media","action":"playpause"}
```

## Решение проблем

- **Сервер не видно с iPhone**: убедись, что оба устройства в одной Wi-Fi сети
- **Мышь не двигается**: проверь Accessibility-разрешение для сервера
- **Медиаклавиши не работают**: перезапусти серверное приложение после выдачи разрешений
- **Подключение теряется**: включи авто-переподключение на вкладке «Связь»

## Технологии

- SwiftUI, @Observable (Swift 5.9+)
- Network.framework (Bonjour, NWListener, NWConnection, NWBrowser)
- MultipeerConnectivity (Bluetooth fallback)
- CGEvent (управление мышью и клавиатурой)
- IOKit HID (медиаклавиши)
- Без внешних зависимостей — только Apple frameworks
