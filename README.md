# YTMod

Sideload-friendly YouTube mod for iOS (стиль uYouPlus): свой Theos-твик + GitHub Actions, который впекает его и набор публичных расширений в твой **расшифрованный** YouTube IPA.

## Что внутри

Свой твик (`Sources/Tweak.x`):
- Снятие рекламы (preroll/midroll, брендовые оверлеи, shelf-реклама).
- Фоновое воспроизведение (`AVAudioSession.playback`).
- Picture-in-Picture разрешён всегда.
- Скрытие вкладки Shorts и `YTReelHeaderView`.

Настройки (`Sources/SettingsUI.x` + `Settings.x`):
- Встраивается в YouTube Settings → General разделом **YTMod** с переключателями (Block ads, Background, PiP, Hide Shorts, Downloader, …).
- Fallback: долгий тап по аватарке в аккаунт-меню тоже открывает экран.
- Хранится в `Documents/ytmod.plist` внутри контейнера приложения (переживает перезапуск, стирается при переустановке IPA).

Локализация (`Sources/L10n.x` + `Resources/YTModResources.bundle`):
- Языки: en, ru, kk, uk, es, de, fr, pt-BR, ja, zh-Hans.
- По умолчанию берётся язык системы; в экране YTMod → **Язык** можно выбрать вручную (применяется сразу).
- В IPA бандл кладётся в корень `YouTube.app` (через `cyan -f`), в .deb — в `/Library/Application Support/YTMod/`.
- Добавить язык: создай `Resources/YTModResources.bundle/<код>.lproj/Localizable.strings`, скопировав ключи из `en.lproj`. Ключи `muxed_fmt` / `muxed_mp4_fmt` — format-строки, порядок `%@` не меняй.

Автоматически подтягиваются в сборку (если доступны релизы):
- YouTubeSponsorBlock
- YouPiP
- YTUHD
- Return YouTube Dislikes
- YouTubeHeader (общие заголовки)

Встроенный **downloader** (`Sources/Downloader.x`):
- Хукает `YTIPlayerResponse.streamingData` и запоминает список `formats`/`adaptiveFormats`.
- Заменяет кнопку Share в оверлее плеера на action-sheet с выбором: видео по разрешениям (muxed MP4 до 720p), audio-only (M4A), или системный Share.
- Качает через `NSURLSession`, видео сохраняется в Photos, аудио — в системный share-пикер (Files/AirDrop).
- **1080p / 1440p / 4K**: отдельные video-only и audio-only дорожки. Downloader:
  1. При необходимости расшифровывает `signatureCipher` через `SigDecipher` (качает `base.js` плеера, парсит JS-функции и гоняет их через `JavaScriptCore`).
  2. Качает обе дорожки параллельно во временную папку.
  3. Склеивает через `AVMutableComposition` + `AVAssetExportSession` в один `.mp4` (passthrough, без перекодирования — быстро).
  4. **Только H.264 + AAC**. VP9/AV1/Opus iOS не упакует — такие варианты не показываются в списке.
- Если плеер YouTube обновится и регэкспы в `SigDecipher.x` перестанут матчиться, decipher упадёт с сообщением "regex miss" — тогда обнови паттерны `kSigNamePat` / `kNFuncPat` (сверяйся с [yt-dlp/extractor/youtube.py](https://github.com/yt-dlp/yt-dlp/blob/master/yt_dlp/extractor/youtube/_video.py)).
- Для Photos CI автоматически добавляет `NSPhotoLibraryAddUsageDescription` в Info.plist.

## Структура

```
Makefile              # Theos tweak build
control               # deb metadata
YTMod.plist           # bundle filter -> com.google.ios.youtube
Sources/
  Tweak.x             # основные хуки
  Settings.x          # чтение prefs plist
  Settings.h
.github/workflows/
  build.yml           # macos-14 runner: Theos + cyan + repack
```

## Как собрать (GitHub Actions)

1. Запушь этот репо на GitHub.
2. Залей расшифрованный YouTube IPA куда-то, откуда CI может его скачать по прямой ссылке (приватный R2/S3, GitHub Release на приватном репо с токеном, и т.п.). **Chrome-store / App Store ссылки не подойдут — нужен decrypted IPA.**
3. Actions → **Build YTMod IPA** → Run workflow → укажи `ipa_url`.
4. Скачай `YTMod.ipa` из артефактов джоба.

## Как поставить

- **TrollStore** (iOS 14.0–16.6.1, 17.0): просто открой `.ipa`.
- **AltStore / SideStore**: добавь IPA, подпиши своим Apple ID (7 дней / 1 год для dev account).
- **Sideloadly**: подпиши и установи по USB.

## Локальная сборка (если есть Mac)

```bash
export THEOS=~/theos
make package FINALPACKAGE=1
# .deb появится в packages/
pipx install pyzule-rw
cyan -duwsgq -i YouTube.ipa -o YTMod.ipa -n YTMod -b com.ytmod.youtube \
     -f packages/*.deb /path/to/extras/*.deb
```

## Совместимость

- Протестируй на последней публичной версии YouTube iOS (убедись, что селекторы совпадают).
- При крупном обновлении YouTube классы могут переименоваться — тогда правь `Sources/Tweak.x`. Тулзы для реверса: `class-dump`, `Hopper`, `cyberduck+Filza` для скачивания `YouTube.app/YouTube` с устройства.

## Легалка

Распространение модифицированного YouTube IPA нарушает ToS Google и условия Apple Developer Program. Сборка — для личного использования. Не выкладывай получившийся IPA публично.
