import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:fftea/fftea.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MaterialApp(
    title: "Doppler App" ,// név az alkalmazásváltóban
    home: DopplerApp(),
    debugShowCheckedModeBanner: false,
  ));
}

class DopplerApp extends StatefulWidget {
  const DopplerApp({super.key});

  @override
  State<DopplerApp> createState() => _DopplerAppState();
}

class _DopplerAppState extends State<DopplerApp> {
  final AudioRecorder hangRogzito = AudioRecorder();
  bool rogzitesAktiv = false;
  String allapot = "Indításra kész";
  double sebessegKmh = 0.0;

  Future<void> _feldolgozasFelvetelek(String utvonal) async {
    setState(() => allapot = "Spektrális elemzés folyamatban...");

    try {
      final fajl = File(utvonal);
      if (!await fajl.exists()) {
        setState(() => allapot = "A fajl nem jött létre!");
        return;
      }

      final bajtok = await fajl.readAsBytes();
      final Int16List nyersAdatok = bajtok.buffer.asInt16List();

      const int ablakMeret = 8192;
      const int lepesKoz = 4096;
      const int mintaFrekvencia = 44100;

      if (nyersAdatok.length < ablakMeret * 3) {
        setState(() => allapot = "Túl rövid felvétel!");
        return;
      }

      List<double> szegmensLeker(int kezdet, int hossz) {
        List<double> szegmens = List.filled(hossz, 0.0);
        for (int i = 0; i < hossz; i++) {
          szegmens[i] = nyersAdatok[kezdet + i].toDouble();
        }
        return szegmens;
      }

      // Most már egy listát tárolunk minden pontnál: [frekvencia, hangerő]
      List<List<double>> ervenyesAdatok = [];
      double globalisMaxHangerej = 0.0; // A felvétel legesleghangosabb pontja

      for (int kezdet = 2000; kezdet + ablakMeret < nyersAdatok.length; kezdet += lepesKoz) {
        List<double> eredmeny = _csucsFrekvencia(mintaFrekvencia, szegmensLeker(kezdet, ablakMeret));
        double frekvencia = eredmeny[0];
        double hangerej = eredmeny[1];

        if (frekvencia > 0) {
          ervenyesAdatok.add(eredmeny);
          if (hangerej > globalisMaxHangerej) {
            globalisMaxHangerej = hangerej; // Elmentjük, mekkora volt a leghangosabb duda
          }
        }
      }

      setState(() {
        // Hangerő szűrés: Csak azokat a frekiket tartjuk meg, amik elég hangosak voltak
        // (Elérte a maximális hangerő legalább 20%-át). Ez levágja a távolodó motorzajt!
        List<double> erosFrekvenciak = [];
        for (var adat in ervenyesAdatok) {
          if (adat[1] >= globalisMaxHangerej * 0.20) {
            erosFrekvenciak.add(adat[0]);
          }
        }

        if (erosFrekvenciak.length >= 2) {
          double fMagas = erosFrekvenciak.reduce(max);
          double fAlacsony = erosFrekvenciak.reduce(min);

          if (fMagas == fAlacsony || fMagas - fAlacsony < 10) {
            sebessegKmh = 0.0;
            allapot = "Nem észlelhető egyértelmű Doppler-effektus.";
          } else {
            // Doppler képlet
            sebessegKmh = 343.0 * (fMagas - fAlacsony) / (fMagas + fAlacsony) * 3.6;

            // JAVÍTÁS: Csak a fH és fL értékeket írjuk ki a sok adat helyett
            allapot = "Mérés kész! (${fMagas.round()} Hz -> ${fAlacsony.round()} Hz)";
          }
        } else {
          allapot = "Túl zajos vagy nem volt egyértelmű áthaladás.";
        }
      });
    } catch (e) {
      setState(() => allapot = "Hiba az elemzésnél!");
      print("Kivétel: $e");
    }
  }

  // A matematikai motor most már a [frekvencia, hangerő] párossal tér vissza
  List<double> _csucsFrekvencia(int mintaFrekvencia, List<double> szegmens) {
    final fft = FFT(szegmens.length);
    final spektrum = fft.realFft(szegmens);
    final amplitudok = spektrum.map((c) => sqrt(c.x * c.x + c.y * c.y)).toList();

    int minBin = (300 * szegmens.length / mintaFrekvencia).round();
    int maxBin = (1200 * szegmens.length / mintaFrekvencia).round();

    int csucsIndex = minBin;
    double maxAmplitudo = 0.0;
    double osszAmplitudo = 0.0;

    for (int i = minBin; i < maxBin; i++) {
      osszAmplitudo += amplitudok[i];
      if (amplitudok[i] > maxAmplitudo) {
        maxAmplitudo = amplitudok[i];
        csucsIndex = i;
      }
    }



    double atlagAmplitudo = osszAmplitudo / (maxBin - minBin);

    // JAVÍTÁS: Szigorúbb alapzaj szűrés (5000.0-es küszöb) a csendben mért hülyeségek ellen
    if (maxAmplitudo > atlagAmplitudo * 5.0 && maxAmplitudo > 5000.0) {
      return [csucsIndex * mintaFrekvencia / szegmens.length, maxAmplitudo];
    } else {
      return [0.0, 0.0];
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text("Doppler Sebességmérő 2.0"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
                allapot,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 18)
            ),
          ),
          const SizedBox(height: 30),
          Center(
            child: Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.blueAccent, width: 4),
              ),
              child: Text(
                sebessegKmh.toStringAsFixed(1),
                style: const TextStyle(fontSize: 80, fontWeight: FontWeight.bold, color: Colors.blueAccent),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text("km/h", style: TextStyle(color: Colors.blueAccent, fontSize: 24)),
          const SizedBox(height: 60),
          GestureDetector(
            onLongPressStart: (_) async {
              if (await hangRogzito.hasPermission()) {
                final ideiglenesKonyvtar = await getTemporaryDirectory();
                final fajlUtvonal = "${ideiglenesKonyvtar.path}/meres.wav";

                await hangRogzito.start(
                    const RecordConfig(
                        encoder: AudioEncoder.pcm16bits,
                        sampleRate: 44100,
                        numChannels: 1
                    ),
                    path: fajlUtvonal
                );

                setState(() {
                  rogzitesAktiv = true;
                  allapot = "Rögzítés... Várd meg amíg elhalad az autó!";
                });
              }
            },
            onLongPressEnd: (_) async {
              final fajlUtvonal = await hangRogzito.stop();
              setState(() => rogzitesAktiv = false);
              if (fajlUtvonal != null) await _feldolgozasFelvetelek(fajlUtvonal);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: rogzitesAktiv ? Colors.red : Colors.blueAccent,
                shape: BoxShape.circle,
                boxShadow: [
                  if (rogzitesAktiv)
                    BoxShadow(color: Colors.red.withOpacity(0.6), blurRadius: 30, spreadRadius: 10)
                ],
              ),
              child: const Icon(Icons.mic, color: Colors.white, size: 60),
            ),
          ),
          const SizedBox(height: 30),
          const Text(
              "Kezdd el rögzíteni még mielőtt ideér!",
              style: TextStyle(color: Colors.white54, fontSize: 16, fontWeight: FontWeight.bold)
          ),
        ],
      ),
    );
  }
}