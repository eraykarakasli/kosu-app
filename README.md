# Kosu Uygulamasi - Flutter

Android Studio kullanmadan, sadece Flutter SDK ile Chrome tarayicisinda test edebilecegin koşu takip uygulamasi.

## Ozellikler
- Harita üzerinde konum takibi ve rota cizimi
- Metre cinsinden hedef mesafe girme (ornek: 400m)
- Hedef mesafeye ulasinca otomatik durdurma ve uyari
- Gecen sure ve pace (min/km) hesaplama
- Chrome web üzerinde test imkanı
- Sonradan Android APK olarak derlenebilirlik

## 1. Flutter SDK'yu Kur (Windows)

1. Flutter SDK'yı indir: https://docs.flutter.dev/get-started/install/windows
2. ZIP'i `C:\src\flutter` gibi bir konuma aç
3. `C:\src\flutter\bin` yolunu Windows PATH ortam degiskenine ekle
4. Terminalde (PowerShell) dogrulama icin calistir:
   ```powershell
   flutter doctor
   ```
5. Chrome'u kullanicaksa ekstra kurulum gerekmemektedir.

## 2. Projeyi Calistir (Chrome Web Test)

Terminalde proje dizinine gir:
```powershell
cd "c:\Users\eray1\Desktop\Klasör\kosu\kosu_app"
```

Paketleri yukle:
```powershell
flutter pub get
```

Chrome'da calistir:
```powershell
flutter run -d chrome
```

- Tarayici acilacak ve konum izni isteyecektir. **"Izine Ver"** diyerek onayla.
- Hedef mesafeyi metre olarak gir (ornek: 400).
- "Koşmaya Başla" basarak konum takibini baslat.
- Hedefe ulasinca otomatik durur ve sonuc (mesafe, sure, pace) goruntulenir.

## 3. Android APK Çıkarmak İstiyorsan (Sonradan)

APK almak icin Android SDK'ye ihtiyacin olacak. Flutter ile:

```powershell
flutter build apk --release
```

Olusan APK dosyasi buraya olusur:
```
build/app/outputs/flutter-apk/app-release.apk
```

Bu dosyayı telefonuna kopyalayip kurabilirsin. (Telefon ayarlarindan "Bilinmeyen kaynaklardan yukleme" iznini vermen gerekebilir.)

## Dosya Yapisi
```
kosu_app/
  pubspec.yaml          # Flutter bagimliliklari
  lib/
    main.dart           # Tam uygulama kodu
```

## Kullanılan Paketler
- `flutter_map` — Harita gosterimi (OpenStreetMap, API anahtarı gerekmez)
- `latlong2` — Koordinat hesaplamalari
- `geolocator` — Konum takibi (Chrome web ve Android'de calisir)
