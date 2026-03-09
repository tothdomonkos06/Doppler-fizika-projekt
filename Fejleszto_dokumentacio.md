# 🎵 Doppler Sebességmérő – Fejlesztői Dokumentáció

> **Verzió:** 2.0  
> **Platform:** Flutter (Android / iOS)  
> **Nyelv:** Dart  

---

## Tartalomjegyzék

1. [Projekt áttekintés](#1-projekt-áttekintés)
2. [Függőségek](#2-függőségek)
3. [Architektúra](#3-architektúra)
4. [Fő komponensek](#4-fő-komponensek)
5. [Algoritmus leírása](#5-algoritmus-leírása)
6. [Adatfolyam](#6-adatfolyam)
7. [Konfiguráció és konstansok](#7-konfiguráció-és-konstansok)
8. [UI struktúra](#8-ui-struktúra)
9. [Ismert korlátok és fejlesztési lehetőségek](#9-ismert-korlátok-és-fejlesztési-lehetőségek)

---

## 1. Projekt áttekintés

Ez az alkalmazás a **Doppler-effektus** elvét alkalmazva becsüli meg egy elhaladó jármű (pl. autó, motor) sebességét, kizárólag a telefon mikrofonját használva.

### Működési elv

Amikor egy hangforrás (pl. dudáló autó) közeledik, a felvett hang frekvenciája **magasabb** a kibocsátottnál. Távolodáskor **alacsonyabb**. A két frekvencia arányából a hangsebesség ismeretében a jármű sebessége kiszámítható.

**Doppler képlet:**

```
v_forrás = c * (f_magas - f_alacsony) / (f_magas + f_alacsony)
```

ahol:
- `c` = hangsebesség levegőben (343 m/s)
- `f_magas` = közeledés közben mért domináns frekvencia
- `f_alacsony` = távolodás közben mért domináns frekvencia

---

## 2. Függőségek

Az alábbi csomagok szükségesek a `pubspec.yaml`-ban:

| Csomag | Verzió | Leírás |
|---|---|---|
| [`record`](https://pub.dev/packages/record) | ^5.x | Mikrofon hozzáférés és WAV rögzítés |
| [`fftea`](https://pub.dev/packages/fftea) | ^1.x | Gyors Fourier-transzformáció (FFT) |
| [`path_provider`](https://pub.dev/packages/path_provider) | ^2.x | Ideiglenes fájlrendszer elérés |

```yaml
dependencies:
  flutter:
    sdk: flutter
  record: ^5.0.0
  fftea: ^1.3.0
  path_provider: ^2.1.0
```


---

## 3. Architektúra

Az alkalmazás egyetlen `StatefulWidget`-re épül, rövid és önálló:

```
DopplerApp (StatefulWidget)
└── _DopplerAppState
    ├── hangRogzito       → AudioRecorder példány
    ├── rogzitesAktiv     → bool – rögzítés folyamatban?
    ├── allapot           → String – felhasználónak megjelenített státusz
    ├── sebessegKmh       → double – kiszámított sebesség
    ├── _feldolgozasFelvetelek()  → WAV elemzés, sebesség számítás
    └── _csucsFrekvencia()        → FFT, domináns frekvencia kinyerése
```

---

## 4. Fő komponensek, függvények

### `AudioRecorder hangRogzito`

A `record` csomag példánya. Konfiguráció:

```dart
RecordConfig(
  encoder: AudioEncoder.pcm16bits,  // Nyers PCM, WAV formátum
  sampleRate: 44100,                 // 44,1 kHz mintavételezés
  numChannels: 1                     // Mono csatorna
)
```

A rögzítés az eszköz ideiglenes könyvtárában menti a fájlt (`meres.wav`).

---

### `_feldolgozasFelvetelek(String utvonal)`

**Feladata:** A WAV fájl beolvasása, ablakozása és a Doppler-sebesség kiszámítása.

**Folyamat:**

1. Fájl beolvasása bájt-tömbként → `Int16List` konverzió
2. Csúszó ablakos FFT elemzés (8192 minta, 4096 lépésköz)
3. Minden ablakból `[frekvencia, amplitúdó]` pár kinyerése
4. **Hangerő-alapú szűrés:** csak a globális maximum 20%-át elérő frekvenciák kerülnek tovább. Ennél jobb, és egyszerűen megvalósítható ötetunk sajnos nem volt.
5. Magas és alacsony frekvencia azonosítása, Doppler képlet alkalmazása

**Bemeneti paraméter:**

| Paraméter | Típus | Leírás |
|---|---|---|
| `utvonal` | `String` | A WAV fájl teljes elérési útja |

---

### `_csucsFrekvencia(int mintaFrekvencia, List<double> szegmens)`

**Feladata:** Egyetlen FFT ablak domináns frekvenciájának és amplitúdójának meghatározása.

**Visszatérési érték:** `List<double>` – `[frekvencia_Hz, amplitúdó]`  
Ha nem észlelhető érvényes jel: `[0.0, 0.0]`

**Keresési tartomány:** 300 Hz – 1200 Hz (Hogy a mikrofon által rögzített mélyfrekvenciás zajokat, vagy más magas felhangokat kiszűrjünk)

**Zajszűrő feltételek:**
- A csúcsamplitúdó > az átlag **5-szörösé** (SNR szűrő)
- A csúcsamplitúdó > **5000.0** abszolút küszöb (csend-detekció)

---

## 5. Algoritmus leírása

### Lépések részletesen

```
┌─────────────────────────────────────────────────────────┐
│  1. WAV beolvasás (Int16List)                           │
│     ↓                                                   │
│  2. Csúszó ablakos feldolgozás                          │
│     ablakméret: 8192 minta (~186 ms @ 44100 Hz)        │
│     lépésköz:   4096 minta (~93 ms)                     │
│     kezdőoffset: 2000 minta (eleje átugrása)            │
│     ↓                                                   │
│  3. FFT minden ablakra → amplitúdó spektrum             │
│     ↓                                                   │
│  4. Csúcs keresése 300–1200 Hz tartományban             │
│     ↓                                                   │
│  5. Érvényesség ellenőrzés (SNR + abszolút küszöb)      │
│     ↓                                                   │
│  6. Hangerő-alapú szűrés                                │
│     (csak max_amplitúdó * 0.20 fölöttiek maradnak)      │
│     ↓                                                   │
│  7. f_magas és f_alacsony azonosítása                   │
│     ↓                                                   │
│  8. Doppler képlet → km/h                               │
└─────────────────────────────────────────────────────────┘
```


## 6. Adatfolyam

```
Felhasználó lenyomja a gombot
        │
        ▼
hangRogzito.start() → meres.wav írás
        │
Felhasználó felemeli a gombot
        │
        ▼
hangRogzito.stop() → fájlútvonal
        │
        ▼
_feldolgozasFelvetelek(utvonal)
        │
   ┌────┴────┐
   │  FFT    │  × N ablak
   └────┬────┘
        │ [frekvencia, amplitúdó] párok
        ▼
Hangerő szűrés (>= maxAmplitudo * 0.20) primitív módszer ugyan, de nem volt jobb ötletünk.
        │
        ▼
f_magas = max(erosFrekvenciak)
f_alacsony = min(erosFrekvenciak)
        │
        ▼
sebessegKmh = 343 * (fM - fA) / (fM + fA) * 3.6
        │
        ▼
setState() → UI frissítés
```

---

## 7. Konfiguráció és konstansok

| Konstans | Érték | Leírás |
|---|---|---|
| `ablakMeret` | `8192` | FFT ablakméret (minták száma) |
| `lepesKoz` | `4096` | Csúszó ablak lépésköze |
| `mintaFrekvencia` | `44100` | Mintavételezési frekvencia (Hz) |
| `minBin` | `300 Hz` | FFT keresési tartomány alja |
| `maxBin` | `1200 Hz` | FFT keresési tartomány teteje |
| SNR küszöb | `5.0×` | Csúcs / átlag amplitúdó arány |
| Abszolút küszöb | `5000.0` | Minimális csúcsamplitúdó |
| Hangerő-szűrő | `0.20` | Maximális amplitúdó hányada |
| Hangsebesség | `343.0 m/s` | Levegőben, ~20°C-on |
| Minimális Δf | `10 Hz` | Ez alatti különbség: nem Doppler |

---

## 8. UI struktúra

```
Scaffold (háttér: Colors.grey[900])
├── AppBar – "Doppler Sebességmérő 2.0"
└── Column (center)
    ├── Text – állapotüzenet (allapot)
    ├── Container (kör) – sebesség kijelzés (km/h)
    ├── Text – "km/h" felirat
    └── GestureDetector (hosszú nyomás)
        ├── onLongPressStart → rögzítés indítás
        ├── onLongPressEnd   → rögzítés leállítás + elemzés
        └── AnimatedContainer (gomb)
            └── Icon(Icons.mic)
                (kék = várakozás, piros = rögzítés)
```

### Állapotok és megjelenésük

| Állapot | `allapot` szöveg | Gomb szín |
|---|---|---|
| Alapállapot | "Indításra kész" | Kék |
| Rögzítés közben | "Rögzítés... Várd meg..." | Piros (fénylő, árnyékot vet) |
| Elemzés közben | "Spektrális elemzés folyamatban..." | Kék |
| Sikeres mérés | "Mérés kész! (XXXX Hz -> XXXX Hz)" | Kék |
| Nem egyértelmű | "Nem észlelhető egyértelmű Doppler-effektus." | Kék |
| Túl rövid | "Túl rövid felvétel!" | Kék |
| Hiba | "Hiba az elemzésnél!" | Kék |

---

## 9. Ismert korlátok és fejlesztési lehetőségek

### Jelenlegi korlátok

- **Statikus frekvenciatartomány:** A 300–1200 Hz csak duda/motor hangokra optimalizált, sokszor alacsony zajok megzavarják a felvételt, ami ezáltal használhatatlan lesz. Jelenleg ez a legnagyobb probléma.
- **Hőmérséklet-függőség:** A hangsebesség (`343 m/s`) szobahőmérsékletre van rögzítve. Hidegben/melegben ez eltér.
- **Mono felvétel:** Sztereó mikrofon esetén irányfüggő elemzés lehetséges lenne.

### Lehetséges fejlesztések

- [ ] Spektrogram vizualizáció valós időben
- [ ] Mérési napló mentése
- [ ] Adaptív frekvenciatartomány (felhasználói beállítás)
- [ ] Szögkorrekció (cosinus-faktor) a pontosabb eredményért
- [ ] Tesztek hozzáadása (`flutter_test`)


## Érdekességek:

- **Amikor hangfelvételeken teszteltük az alkalmazást**, arra lettünk figyelmesek, hogy több féle duda is létezik. Többségük egy hangot bocsájt ki mint egy kürt, de némelyik mint egy rezesbanda több hangon szólal meg egyszerre. Ezeknél a járműveknél igencsak megnehezedik a program használata.

- **A videófelvétel készítése során** keresnünk kellett egy forgalomtól kissé elzártabb útszakaszt, ahol felgyorsulni, de megállni és visszafordulni is lehet, valamint a dudaszóval sem zavarunk senkit. Végül Biatorbágyon találtunk egy ilyen helyszínt. Nagyon élveztük a forgatást.



