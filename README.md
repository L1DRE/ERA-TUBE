# YTMod

Мод YouTube для iOS (стиль uYouPlus). GitHub Actions собирает файлы мода, а Sideloadly встраивает их в **расшифрованный** `YouTube.ipa` и ставит на iPhone.

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
- `YTModResources.bundle` упакован внутрь `YTMod.deb`; Sideloadly при установке кладёт его в `YouTube.app`.
- Добавить язык: создай `Resources/YTModResources.bundle/<код>.lproj/Localizable.strings`, скопировав ключи из `en.lproj`. Ключи `muxed_fmt` / `muxed_mp4_fmt` — format-строки, порядок `%@` не меняй.

Пропуск спонсорских вставок (`Sources/SponsorBlock.x`):
- Встроен в мод, отдельный твик не нужен. Отрезки берутся из открытого API [SponsorBlock](https://sponsor.ajay.app): sponsor, self-promo, interaction.
- На сервер уходят только первые 4 символа SHA-256 от ID видео, так что он не знает, какое видео ты смотришь.
- Включается в YTMod → Воспроизведение → «Пропускать спонсорские вставки».

Дополнительные твики в архиве сборки:
- **YouPiP** и **YTUHD** — свежая версия из репозитория PoomSmart (`poomsmart.github.io/repo`).
- **Return YouTube Dislike** — собирается из исходников [PoomSmart/Return-YouTube-Dislikes](https://github.com/PoomSmart/Return-YouTube-Dislikes), вместе с ресурсами `RYD.bundle`.
- Если какой-то из них не скачается или не соберётся, архив всё равно будет, просто без него.

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
- Сохранение в Фото работает, если в `Info.plist` YouTube есть разрешение на доступ к Фото. Если его нет, видео открывается в меню «Поделиться» → «Сохранить в Файлы».

## Структура

```
Makefile              # сборка твика (Theos)
control               # метаданные .deb
YTMod.plist           # фильтр: грузиться только в com.google.ios.youtube
Sources/              # код мода
Resources/
  YTModResources.bundle   # переводы интерфейса
.github/workflows/
  build.yml           # сборка файлов мода на GitHub
```

## Как собрать

Сборка запускается сама при каждом пуше в `main`. Запустить вручную: **Actions → Build YTMod for Sideloadly → Run workflow**.

Когда она закончится, внизу страницы запуска в разделе **Artifacts** будет архив `YTMod-for-Sideloadly`. Скачай и распакуй его, внутри:
- `YTMod.deb` — сам мод;
- `.deb` дополнительных твиков (YouPiP, YTUHD, Return Dislike).

Переводы (`YTModResources.bundle`) и ресурсы Return Dislike (`RYD.bundle`) лежат внутри своих `.deb`, Sideloadly достаёт их сам.

## Как поставить (Sideloadly)

1. Нужен **расшифрованный** `YouTube.ipa` (из App Store он зашифрован и не подойдёт).
2. Открой Sideloadly, перетащи в него `YouTube.ipa`, введи свой Apple ID.
3. **Advanced options → Tweak injection → Inject dylibs/frameworks** — добавь все `.deb` из архива. Папки `.bundle` отдельно не добавляй: они уже внутри `.deb`, и Sideloadly выдаст ошибку «Duplicated name».
4. Подключи iPhone по кабелю и нажми **Start**.
5. На iPhone: **Настройки → Конфиденциальность и безопасность → Режим разработчика** — включить (пункт появляется после первой установки). Потом **Настройки → Основные → VPN и управление устройством** — доверять своему Apple ID.

С бесплатным Apple ID приложение работает 7 дней, потом переустанови его через Sideloadly тем же способом (данные сохранятся).

## Совместимость

- Протестируй на последней публичной версии YouTube iOS (убедись, что селекторы совпадают).
- При крупном обновлении YouTube классы могут переименоваться — тогда правь `Sources/Tweak.x`. Для разбора бинарника YouTube подойдут `class-dump` и `Hopper`.

## Легалка

Распространение модифицированного YouTube IPA нарушает ToS Google и условия Apple Developer Program. Сборка — для личного использования. Не выкладывай получившийся IPA публично.
