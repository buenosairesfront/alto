// U-MA Flagship — engine con modulación completa por LFO
// POLIFÓNICO: cada nota crea sus 3 capas (voz A/B/C, cada una con su motor)
// y se liberan solas al terminar el release. Hasta 6 notas sostenidas y 6
// colas de release (las más viejas se cortan rápido): así un arp rápido con
// release largo no satura la CPU de la Pi.
// Cada capa (voz) tiene:
//   motor ("kind") elegible entre 19: sine/square/tri/fm/phy, polyperc y
//   polyperc pad (norns), pluck/gendy/formant/pmosc/blip/lfcub/syncsaw/
//   logistic/pinknoise (SuperCollider) y blitb3saw/vosim (sc3-plugins).
//   MdaPiano y OteyPiano (sc3-plugins) quedaron afuera: en esta norns crearlos
//   corrompe el servidor y scsynth se cuelga un rato después (probado).
//   Cada motor es un SynthDef propio: solo corre el oscilador elegido, y al
//   cambiar de motor se reemplaza el synth de esa voz conservando sus valores
//   ruido morphing (white/pink/brown/random) vía crossfade manual
//   ring modulator propio (oscilador carrier + modulador + mix)
//   wave folder propio
//   envolvente attack/decay/sustain/release
//   TODO parámetro numérico es modulable por cualquiera de los 3 LFOs
//   globales (bus de control + amount, por destino)
// Post-mezcla: filtro compartido (kind/poles/cutoff, modulable por LFO,
// por 2 envolventes ADSR que siguen a las notas, y con keytrack)
//
// NO modulable por LFO: "gate" y "leg arp" del arpegiador — son decisiones
// de secuenciamiento que vive del lado de la Lua, no parámetros de audio.
//
// CPU (norns Pi 3): todo lo que no suena no se calcula.
//   - las voces se pausan solas (doneAction 1) al terminar el release y se
//     reactivan en cada noteOn
//   - el filtro es un synth por combinación kind/poles: solo corren las
//     etapas en uso (se reemplaza el synth al cambiar kind o poles)
//   - cada efecto es un synth propio que existe solo mientras está en ON
//   - la cadena es mono hasta la salida (las voces siempre estuvieron en
//     el centro, el estéreo solo duplicaba el cálculo)

Engine_UmaFlagship : CroneEngine {
	var voiceArgs, voiceKind, layerGroups, notes, noteFreqs, noteOrder, tails;
	var lfoBuses, lfoSynths, zeroBus;
	var mixBus, fxBus;
	var lfoGroup, voiceGroup, filterGroup, fxGroup, outGroup;
	var filterSynth, filterState, filterArgKeys, outSynth;
	var envBuses, envSynths, lastEnvRetrig;
	var fxOrder, fxGroups, fxSynths, fxParams;

	*new { arg context, doneCallback;
		^super.new(context, doneCallback);
	}

	*filterDefName { arg kind, poles;
		^("uma_filter_" ++ kind ++ "_" ++ poles).asSymbol
	}

	// motores disponibles por voz — el índice es lo que manda la Lua con "kind"
	*voiceKinds {
		^[\sine, \square, \tri, \fm, \phy,
			\polyperc, \polypercPad,
			\pluck, \gendy, \formant, \pmosc, \blip, \lfcub, \syncsaw, \logistic, \pinknoise,
			\blitb3saw, \vosim]
	}

	// full = con ruido / ring mod / wave folder por voz. La versión liviana
	// (sin esas etapas) cuesta mucho menos CPU y es la que se usa casi siempre
	*voiceDefName { arg kindNum, full = true;
		^("uma_voice_" ++ kindNum ++ if(full, { "" }, { "_lite" })).asSymbol
	}

	// el oscilador de cada motor. pwm (0-1), fmCarrier (ratio) y fmAmount (0-1)
	// funcionan como perillas de timbre propias de cada uno. gate = gate
	// efectivo (con re-disparo), para los motores con ataque propio.
	*voiceOsc { arg kindNum, freq, pwm, fmCarrier, fmAmount, gate;
		^switch(kindNum,
			0, { SinOsc.ar(freq) },
			1, { Pulse.ar(freq, pwm) },
			2, { LFTri.ar(freq) },
			3, { SinOsc.ar(freq + SinOsc.ar(freq * fmCarrier, 0, freq * fmAmount * 4)) },
			4, {
				var shaped = (Saw.ar(freq) * 4).tanh;
				// Ringz no está normalizado: su ganancia crece con decay x freq
				// (a 220 Hz era ~x300 y saturaba todo). Se divide por eso.
				var modes = Mix.ar(Array.fill(3, { |i|
					var f = freq * (i + 1) * (1 + (0.02 * (i + 1)));
					Ringz.ar(shaped, f, 0.25) / (0.25 * f * 2.5)
				}));
				(shaped * 0.3) + (modes * 0.5)
			},
			// polyperc (norns): pulso -> MoogFF, con golpe percusivo propio
			// que abre el filtro y decae aunque la nota siga sostenida
			5, {
				var perc = EnvGen.kr(Env.perc(0.003, 0.9, 1, -4), gate);
				MoogFF.ar(Pulse.ar(freq, pwm), (freq * 1.5) + (5000 * perc), 2) * perc * 1.6
			},
			// polyperc pad: el mismo circuito, abierto y sostenido, dos pulsos
			// desafinados apenas con pwm que respira lento
			6, {
				var pw = (pwm + SinOsc.kr(0.23, 0, 0.12)).clip(0.05, 0.95);
				var src = Mix.ar(Pulse.ar(freq * [0.996, 1.004], pw)) * 0.5;
				MoogFF.ar(src, (freq * 3) + SinOsc.kr(0.11).range(200, 1600), 1.5) * 2.6
			},
			// pluck: cuerda Karplus-Strong excitada con ruido en cada ataque
			7, {
				Pluck.ar(WhiteNoise.ar(0.6), gate, 0.05, freq.max(20).reciprocal, 4, 0.2 + (pwm * 0.6)) * 1.4
			},
			// gendy: síntesis estocástica de Xenakis alrededor de la nota
			8, {
				LeakDC.ar(Gendy1.ar(1, 1, 1, 1, freq, freq * (1.01 + (fmAmount * 0.1)), 0.3, 0.05, 12)) * 1.1
			},
			// formant: fundamental + formante (pwm mueve la formante)
			9, {
				Formant.ar(freq, freq * (1.5 + (pwm * 6)), freq * 1.5) * 0.8
			},
			// pmosc: modulación de fase (carrier ratio + índice)
			10, {
				PMOsc.ar(freq, freq * fmCarrier, fmAmount * 6)
			},
			// blip: tren de pulsos limitado en banda (pwm = cantidad de armónicos)
			11, {
				Blip.ar(freq, (2 + (pwm * 30)).round) * 3.5
			},
			// lfcub: forma cúbica, entre seno y triángulo
			12, {
				LFCub.ar(freq) * 0.9
			},
			// syncsaw: sierra esclava sincronizada (pwm = relación esclava)
			13, {
				SyncSaw.ar(freq, freq * (1.2 + (pwm * 5))) * 1.1
			},
			// logistic: mapa logístico caótico iterado a la frecuencia de la nota
			14, {
				LeakDC.ar((Logistic.ar(3.55 + (pwm * 0.44), freq * 2, 0.5) - 0.5) * 2) * 1.2
			},
			// pinknoise: ruido rosa crudo + una resonancia afinada en la nota
			15, {
				var pink = PinkNoise.ar;
				((pink * 0.35) + (Resonz.ar(pink, freq, 0.02) * 6)) * 3
			},
			// blitb3saw (sc3-plugins): sierra BLIT sin aliasing
			16, {
				BlitB3Saw.ar(freq, 0.99) * 1.2
			},
			// vosim (sc3-plugins): pulsos vocales (pwm = formante)
			17, {
				VOSIM.ar(Impulse.ar(freq), freq * (2 + (pwm * 6)), 3, 0.9) * 3.5
			}
		)
	}

	*synthDefs {
		var defs = List.new;

		// ---- voces: un SynthDef por motor (ver *voiceKinds / *voiceOsc) ----
		[true, false].do { |full|
		this.voiceKinds.size.do { |kindNum|
		defs.add(SynthDef(this.voiceDefName(kindNum, full), {
			arg out=0, gate=0, t_retrig=0, freq=220, octMul=1,
			pwm=0.5,
			fmCarrier=1, fmAmount=0,
			harmonic=1,
			noiseKind=0,     // 0=white 1=pink 2=brown 3=random (float, morphea con crossfade manual)
			noiseAmount=0,
			att=0.01, dec=0.3, sus=1, rel=0.5,
			ringOn=1, ringCarRatio=1, ringModFreq=100, ringMix=0,
			wfOn=1, wfAmount=0, wfMain=0.5, wfOffset=0,
			voiceOn=1,
			// ---- modulación por LFO: bus a leer + profundidad, por destino ----
			enabledModBus=0, enabledModAmt=0,
			kindModBus=0, kindModAmt=0, // sin efecto: el motor ya no es continuo
			pwmModBus=0, pwmModAmt=0,
			fmCarrierModBus=0, fmCarrierModAmt=0,
			fmAmountModBus=0, fmAmountModAmt=0,
			octaveModBus=0, octaveModAmt=0,
			harmonicModBus=0, harmonicModAmt=0,
			attModBus=0, attModAmt=0,
			decModBus=0, decModAmt=0,
			relModBus=0, relModAmt=0,
			noiseAmountModBus=0, noiseAmountModAmt=0,
			noiseKindModBus=0, noiseKindModAmt=0,
			ringOnModBus=0, ringOnModAmt=0,
			ringCarModBus=0, ringCarModAmt=0,
			ringModFreqModBus=0, ringModFreqModAmt=0,
			ringMixModBus=0, ringMixModAmt=0,
			wfOnModBus=0, wfOnModAmt=0,
			wfAmountModBus=0, wfAmountModAmt=0,
			wfMainModBus=0, wfMainModAmt=0,
			wfOffsetModBus=0, wfOffsetModAmt=0,
			amp=0.3;

			var sig, noises, noiseSig, ringSig, folded, env, envGate, modFreq;
			var noiseKindIdx, ringOnFinal, wfOnFinal, voiceOnFinal;
			var noiseKindLow, noiseKindFrac;

			// suavizado: los parámetros que se tocan en vivo con los knobs
			// deslizan en vez de saltar de golpe (evita el "corte digital")
			pwm = pwm.lag(0.05);
			fmCarrier = fmCarrier.lag(0.05);
			fmAmount = fmAmount.lag(0.05);
			noiseAmount = noiseAmount.lag(0.05);
			ringCarRatio = ringCarRatio.lag(0.05);
			ringModFreq = ringModFreq.lag(0.05);
			ringMix = ringMix.lag(0.05);
			wfAmount = wfAmount.lag(0.05);
			wfMain = wfMain.lag(0.05);
			wfOffset = wfOffset.lag(0.05);
			amp = amp.lag(0.05);

			// gate efectivo: t_retrig lo baja durante un solo bloque de control
			// para forzar el re-disparo (lo usan la envolvente y los motores
			// que tienen ataque propio: polyperc, pluck)
			envGate = gate * (1 - Trig1.kr(t_retrig, ControlDur.ir));

			// ---- pitch: freq + vibrato (modulación de "octave") ----
			modFreq = freq * octMul * (2 ** ((In.kr(octaveModBus) * octaveModAmt) / 12));

			// ---- pwm / fm modulables: los motores los usan como "timbre" ----
			pwm = (pwm + (In.kr(pwmModBus) * pwmModAmt * 0.5)).clip(0.01, 0.99);
			fmCarrier = (fmCarrier + (In.kr(fmCarrierModBus) * fmCarrierModAmt * 4)).max(0.1);
			fmAmount = (fmAmount + (In.kr(fmAmountModBus) * fmAmountModAmt)).clip(0, 1);

			// ---- armónico: número modulable (wobble) ----
			harmonic = (harmonic + (In.kr(harmonicModBus) * harmonicModAmt * 3)).clip(1, 8);

			// ---- el motor de esta voz ----
			sig = this.voiceOsc(kindNum, modFreq, pwm, fmCarrier, fmAmount, envGate);

			if(full, {
				// ---- armónico agregado: capa fina de senoidal, sutil ----
				sig = sig + (SinOsc.ar(modFreq * harmonic) * 0.12);

				// ---- ruido propio, morphing continuo entre tipos ----
				noises = [WhiteNoise.ar, PinkNoise.ar, BrownNoise.ar, LFNoise0.ar(modFreq * 4)];
				noiseKindIdx = ((noiseKind * (1 - noiseKindModAmt))
					+ ((((In.kr(noiseKindModBus) + 1) / 2) * 3) * noiseKindModAmt)).clip(0, 3);
				noiseKindLow = noiseKindIdx.floor;
				noiseKindFrac = noiseKindIdx - noiseKindLow;
				noiseSig = (Select.ar(noiseKindLow, noises) * (1 - noiseKindFrac))
					+ (Select.ar((noiseKindLow + 1).min(3), noises) * noiseKindFrac);
				noiseAmount = (noiseAmount + (In.kr(noiseAmountModBus) * noiseAmountModAmt)).clip(0, 1);
				sig = sig + (noiseSig * noiseAmount);

				// ---- ring modulator: oscilador carrier x modulador propio ----
				ringCarRatio = (ringCarRatio + (In.kr(ringCarModBus) * ringCarModAmt * 4)).max(0.05);
				ringModFreq = (ringModFreq + (In.kr(ringModFreqModBus) * ringModFreqModAmt * 500)).max(0.5);
				ringMix = (ringMix + (In.kr(ringMixModBus) * ringMixModAmt)).clip(0, 1);
				ringSig = SinOsc.ar(modFreq * ringCarRatio) * SinOsc.ar(ringModFreq);
				ringOnFinal = (ringOn * (1 - ringOnModAmt))
					+ ((((In.kr(ringOnModBus) + 1) / 2).round) * ringOnModAmt);
				sig = Select.ar(ringOnFinal, [sig, XFade2.ar(sig, ringSig, (ringMix * 2) - 1)]);

				// ---- wave folder ----
				wfAmount = (wfAmount + (In.kr(wfAmountModBus) * wfAmountModAmt)).clip(0, 1);
				wfMain = (wfMain + (In.kr(wfMainModBus) * wfMainModAmt)).clip(0, 1);
				wfOffset = (wfOffset + (In.kr(wfOffsetModBus) * wfOffsetModAmt)).clip(-1, 1);
				folded = ((sig * (1 + (wfAmount * 4))) + wfOffset).fold2(1) * wfMain;
				wfOnFinal = (wfOn * (1 - wfOnModAmt))
					+ ((((In.kr(wfOnModBus) + 1) / 2).round) * wfOnModAmt);
				sig = Select.ar(wfOnFinal, [sig, XFade2.ar(sig, folded, (wfAmount * 2) - 1)]);

			});

			// ---- envolvente: ataque -> decae hasta "sus" -> sostiene mientras
			// gate=1 -> suelta. att/dec/rel modulables (proporcional al valor base).
			// Al terminar el release el synth de esa nota se libera solo. ----
			att = (att + (In.kr(attModBus) * attModAmt * att)).max(0.001);
			dec = (dec + (In.kr(decModBus) * decModAmt * dec)).max(0.001);
			rel = (rel + (In.kr(relModBus) * relModAmt * rel)).max(0.001);
			env = EnvGen.ar(
				Env.new([0, 1, sus, 0], [att, dec, rel], [3, -2, -4], releaseNode: 2),
				envGate,
				doneAction: 2
			);

			// ---- on/off de la voz entera, modulable (trance-gate) ----
			voiceOnFinal = (voiceOn * (1 - enabledModAmt))
				+ ((((In.kr(enabledModBus) + 1) / 2).round) * enabledModAmt);

			sig = sig * env * amp * voiceOnFinal;
			Out.ar(out, sig);
		}));
		};
		};

		// ---- LFOs: 3 instancias, cada una escribe a su propio bus de control.
		// shape: 0=sine 1=tri 2=square 3=random 4=sh-hard 5=sh-soft ----
		defs.add(SynthDef(\uma_lfo, { arg out=0, shape=0, rate=1;
			var sine, tri, square, rnd, shHard, shSoft, sig;
			sine = SinOsc.kr(rate);
			tri = LFTri.kr(rate);
			square = (LFPulse.kr(rate, 0, 0.5) * 2) - 1;
			rnd = LFNoise2.kr(rate);
			shHard = LFNoise0.kr(rate);
			shSoft = LFNoise0.kr(rate).lag(1 / rate.max(0.01));
			sig = Select.kr(shape, [sine, tri, square, rnd, shHard, shSoft]);
			Out.kr(out, sig);
		}));

		// ---- envolventes de filtro: 2 instancias ADSR, cada una escribe 0-1 a
		// su propio bus de control. Se disparan con las notas (ver noteOn) ----
		defs.add(SynthDef(\uma_env, {
			arg out=0, gate=0, t_retrig=0, att=0.01, dec=0.3, sus=0.7, rel=0.5;
			var envGate;
			envGate = gate * (1 - Trig1.kr(t_retrig, ControlDur.ir));
			Out.kr(out, EnvGen.kr(
				Env.new([0, 1, sus, 0], [att, dec, rel], [3, -2, -4], releaseNode: 2),
				envGate
			));
		}));

		// ---- filtro compartido post-mezcla: un SynthDef por kind x poles ----
		// kind: 0=LP 1=HP 2=BP 3=notch. poles 1-4 (más = pendiente más pronunciada).
		// Solo la primera etapa lleva la resonancia: en cascada, 4 etapas
		// resonantes multiplicaban la ganancia del pico (~20^4 con res alta)
		4.do { |kind|
			(1..4).do { |poles|
				defs.add(SynthDef(this.filterDefName(kind, poles), {
					arg in=0, out=0, cutoff=0.5, res=0.3, modBus=0, modDepth=0,
					env1Bus=0, env1Amt=0, env2Bus=0, env2Amt=0,
					keyFreq=261.626, keyAmt=0;
					var sig, freq, rq, keyRatio;
					sig = In.ar(in, 1);
					cutoff = cutoff.lag(0.15);
					modDepth = modDepth.lag(0.15);
					rq = (1 - res).max(0.05).lag(0.15);
					// depth con menos alcance (0.5x): antes con depth=50 ya se cubría
					// todo el rango de cutoff y el resto del knob no hacía nada más.
					// Las envolventes suman sobre el mismo rango 0-1 (amount -1..1)
					freq = (cutoff
						+ (In.kr(modBus) * modDepth * 0.5)
						+ (In.kr(env1Bus) * env1Amt.lag(0.05))).clip(0, 1);
					// keytrack: con keyAmt=1 el corte sube una octava por octava de
					// teclado, tomando el Do central como referencia (sin cambio)
					keyRatio = (keyFreq.lag(0.01) / 261.626) ** keyAmt.lag(0.05);
					freq = (((freq * 19980) + 20) * keyRatio).clip(20, 18000);
					// barrido de K3 (env2): exponencial, desde el cutoff actual hasta
					// arriba del todo, parejo en todo el espectro
					freq = (freq * ((18000 / freq) ** (In.kr(env2Bus) * env2Amt.lag(0.05)).clip(0, 1))).clip(20, 18000);
					poles.do { |stage|
						var q = if(stage == 0, { rq }, { 1 });
						sig = switch(kind,
							0, { RLPF.ar(sig, freq, q) },
							1, { RHPF.ar(sig, freq, q) },
							2, { BPF.ar(sig, freq, q) },
							3, { BRF.ar(sig, freq, q) }
						);
					};
					Out.ar(out, sig);
				}));
			};
		};

		// ---- effects: cadena fija phaser->vibrato->flanger->distortion->
		// bitcrush->delay. Cada efecto es un synth propio que procesa el bus
		// en su lugar (ReplaceOut) y existe solo mientras está en ON. El gate
		// hace un fundido corto de entrada/salida para que prender o apagar
		// no haga click. ----

		// phaser: 4 allpass de primer orden (FOS) con la frecuencia de corte
		// barrida por un LFO propio. Antes eran AllpassC con decay 0, que en
		// la práctica es un delay simple y sonaba a chorus.
		defs.add(SynthDef(\uma_fx_phaser, { arg bus=0, gate=1, phaserRate=0.3, phaserDepth=0;
			var dry, env, fc, w, coef, wet;
			dry = In.ar(bus, 1);
			env = EnvGen.kr(Env.asr(0.02, 1, 0.05), gate, doneAction: 2);
			fc = LinExp.kr(SinOsc.kr(phaserRate.lag(0.1)), -1, 1, 200, 4000);
			w = (pi * fc / SampleRate.ir).tan;
			coef = (w - 1) / (w + 1);
			wet = dry;
			4.do({ wet = FOS.ar(wet, coef, 1, coef.neg) });
			wet = dry + (wet * phaserDepth.lag(0.1));
			ReplaceOut.ar(bus, (dry * (1 - env)) + (wet * env));
		}));

		// vibrato: delay corto modulado (wobble de afinación)
		defs.add(SynthDef(\uma_fx_vibrato, { arg bus=0, gate=1, vibratoRate=5, vibratoDepth=0;
			var dry, env, lfo, wet;
			dry = In.ar(bus, 1);
			env = EnvGen.kr(Env.asr(0.02, 1, 0.05), gate, doneAction: 2);
			vibratoDepth = vibratoDepth.lag(0.1);
			lfo = SinOsc.kr(vibratoRate.lag(0.1)).range(0.001, 0.001 + (vibratoDepth * 0.004));
			wet = DelayC.ar(dry, 0.02, lfo);
			wet = (dry * (1 - vibratoDepth)) + (wet * vibratoDepth);
			ReplaceOut.ar(bus, (dry * (1 - env)) + (wet * env));
		}));

		// flanger: delay corto modulado + mezcla
		defs.add(SynthDef(\uma_fx_flanger, { arg bus=0, gate=1, flangerRateHz=0.3, flangerTimeAmt=0, flangerDepth=0;
			var dry, env, lfo, wet;
			dry = In.ar(bus, 1);
			env = EnvGen.kr(Env.asr(0.02, 1, 0.05), gate, doneAction: 2);
			lfo = SinOsc.kr(flangerRateHz.lag(0.1)).range(0.001, 0.001 + (flangerTimeAmt.lag(0.1) * 0.008));
			wet = dry + (DelayC.ar(dry, 0.02, lfo) * flangerDepth.lag(0.1));
			ReplaceOut.ar(bus, (dry * (1 - env)) + (wet * env));
		}));

		// distortion: waveshaping + control de tono
		defs.add(SynthDef(\uma_fx_dist, { arg bus=0, gate=1, distTone=0.5, distDrive=0;
			var dry, env, shaped, mix, wet;
			dry = In.ar(bus, 1);
			env = EnvGen.kr(Env.asr(0.02, 1, 0.05), gate, doneAction: 2);
			distDrive = distDrive.lag(0.05);
			shaped = (dry * (1 + (distDrive * 8))).tanh;
			shaped = LPF.ar(shaped, 200 + (distTone.lag(0.05) * 8000));
			mix = distDrive.min(1);
			wet = (dry * (1 - mix)) + (shaped * mix);
			ReplaceOut.ar(bus, (dry * (1 - env)) + (wet * env));
		}));

		// bitcrush
		defs.add(SynthDef(\uma_fx_crush, { arg bus=0, gate=1, crushBits=16, crushRate=44100;
			var dry, env, wet;
			dry = In.ar(bus, 1);
			env = EnvGen.kr(Env.asr(0.02, 1, 0.05), gate, doneAction: 2);
			wet = Decimator.ar(dry, crushRate, crushBits);
			ReplaceOut.ar(bus, (dry * (1 - env)) + (wet * env));
		}));

		// delay con feedback (comb). Máximo 2 s: la Lua manda hasta 2.0 s y
		// antes el buffer era de 1 s (se recortaba la mitad del recorrido)
		defs.add(SynthDef(\uma_fx_delay, { arg bus=0, gate=1, delayTime=0.3, delayFeedback=0;
			var dry, env, wet;
			dry = In.ar(bus, 1);
			env = EnvGen.kr(Env.asr(0.02, 1, 0.05), gate, doneAction: 2);
			wet = dry + CombL.ar(dry, 2.0, delayTime.lag(0.1), delayFeedback * 4);
			ReplaceOut.ar(bus, (dry * (1 - env)) + (wet * env));
		}));

		// excitador armónico global: suma 2º, 3º y 4º armónico (polinomios de
		// Chebyshev sobre la señal normalizada por su propio nivel, así la
		// cantidad de armónicos no depende de cuán fuerte suena)
		defs.add(SynthDef(\uma_fx_harm, { arg bus=0, gate=1, harmAmount=0;
			var dry, env, lvl, x, h, amt;
			dry = In.ar(bus, 1);
			env = EnvGen.kr(Env.asr(0.02, 1, 0.05), gate, doneAction: 2);
			amt = harmAmount.lag(0.1);
			lvl = Amplitude.ar(dry, 0.005, 0.05).max(0.0005);
			x = (dry / lvl).clip(-1, 1);
			h = (((2 * x * x) - 1) * 0.5)
				+ (((4 * x * x * x) - (3 * x)) * 0.35)
				+ (((8 * x * x * x * x) - (8 * x * x) + 1) * 0.2);
			h = LeakDC.ar(h) * lvl;
			ReplaceOut.ar(bus, dry + (h * amt * 1.2 * env));
		}));

		// espacio (E1): de 0 a la mitad, nube de delay granular al tempo; de la
		// mitad a 1, se suma un shimmer (reverb cuya cola vuelve una octava arriba)
		defs.add(SynthDef(\uma_fx_space, { arg bus=0, gate=1, spaceAmount=0, beat=0.5;
			var dry, env, amt, aG, aS, fb, src, taps, cloud, verbIn, verb, wet;
			dry = In.ar(bus, 1);
			env = EnvGen.kr(Env.asr(0.05, 1, 3), gate, doneAction: 2);
			amt = spaceAmount.lag(0.4);
			aG = (amt * 2).clip(0, 1);
			aS = ((amt * 2) - 1).clip(0, 1);
			beat = beat.lag(0.5).clip(0.1, 1.2);
			fb = LocalIn.ar(2);
			// nube: granitos cortos de la señal retrasada (corchea con puntillo
			// y corchea), con un poco de realimentación
			src = dry + (fb[0] * 0.4 * aG);
			taps = [
				DelayC.ar(src, 2, (beat * 0.75) + LFNoise1.kr(0.3).range(0, 0.02)),
				DelayC.ar(src, 2, (beat * 0.5) + LFNoise1.kr(0.23).range(0, 0.02))
			];
			cloud = GrainIn.ar(1, Dust.kr(16 + (aG * 20)), LFNoise1.kr(0.5).range(0.06, 0.18), taps[0], 0, -1, 64)
				+ GrainIn.ar(1, Dust.kr(12 + (aG * 16)), LFNoise1.kr(0.4).range(0.08, 0.22), taps[1], 0, -1, 64);
			// varios granos se superponen: se compensa para que la nube no crezca sola
			cloud = LPF.ar(cloud, 5000) * 0.26;
			// shimmer: la cola de la reverb vuelve a entrar una octava arriba
			verbIn = dry + (PitchShift.ar(fb[1], 0.2, 2, 0.002, 0.01) * 0.35 * aS);
			verb = FreeVerb.ar(verbIn, 1, 0.85, 0.45);
			LocalOut.ar([cloud, verb].softclip);
			wet = dry + (cloud * aG * 0.8) + (verb * aS * 0.55);
			ReplaceOut.ar(bus, (dry * (1 - env)) + (wet * env));
		}));

		// ring modulator global: la mezcla multiplicada por un seno (ringFreq Hz),
		// ringMix = cuánto de la señal modulada se mezcla con la original
		defs.add(SynthDef(\uma_fx_ring, { arg bus=0, gate=1, ringFreq=200, ringMix=0;
			var dry, env, wet, mix;
			dry = In.ar(bus, 1);
			env = EnvGen.kr(Env.asr(0.02, 1, 0.05), gate, doneAction: 2);
			mix = ringMix.lag(0.05);
			wet = (dry * (1 - mix)) + (dry * SinOsc.ar(ringFreq.lag(0.05)) * mix);
			ReplaceOut.ar(bus, (dry * (1 - env)) + (wet * env));
		}));

		// reverb limpia (página de efectos): verbMix = cuánto, verbRoom = tamaño
		defs.add(SynthDef(\uma_fx_verb, { arg bus=0, gate=1, verbMix=0, verbRoom=0.6;
			var dry, env, wet;
			dry = In.ar(bus, 1);
			env = EnvGen.kr(Env.asr(0.05, 1, 2), gate, doneAction: 2);
			wet = FreeVerb.ar(dry, verbMix.lag(0.1).clip(0, 1), verbRoom.lag(0.2).clip(0, 1), 0.45);
			ReplaceOut.ar(bus, (dry * (1 - env)) + (wet * env));
		}));

		// wave folder global: pliega la mezcla (amount) con asimetría (sym)
		defs.add(SynthDef(\uma_fx_fold, { arg bus=0, gate=1, foldAmount=0, foldSym=0;
			var dry, env, wet;
			dry = In.ar(bus, 1);
			env = EnvGen.kr(Env.asr(0.02, 1, 0.05), gate, doneAction: 2);
			foldAmount = foldAmount.lag(0.05);
			wet = LeakDC.ar(((dry * (1 + (foldAmount * 7))) + (foldSym.lag(0.05) * 0.6)).fold2(0.8));
			wet = (dry * (1 - foldAmount.min(1))) + (wet * foldAmount.min(1).sqrt);
			ReplaceOut.ar(bus, (dry * (1 - env)) + (wet * env));
		}));

		// salida: mono -> estéreo. -3 dB para igualar el nivel que daba antes
		// Pan2 en el centro
		defs.add(SynthDef(\uma_out, { arg in=0, out=0;
			// limitador: con polifonía los acordes suman, esto evita que clipee
			Out.ar(out, Limiter.ar(In.ar(in, 1) * -3.dbamp, 0.95, 0.01) ! 2);
		}));

		^defs
	}

	alloc {
		var addModCmd, filterArgs, setFilterState, setFxOn, setFxParams, envNoteOn, envNoteOff;
		var setVoice, setKind, startLayer, releaseNote;

		this.class.synthDefs.do({ |def| def.add });

		context.server.sync;

		// bus que siempre vale 0 — "sin modulación" para cualquier destino
		zeroBus = Bus.control(context.server, 1);
		zeroBus.set(0);

		lfoBuses = Array.fill(3, { Bus.control(context.server, 1) });
		envBuses = Array.fill(2, { Bus.control(context.server, 1) });

		// bus intermedio donde suman las 3 voces, antes del filtro compartido
		mixBus = Bus.audio(context.server, 1);
		// bus entre el filtro y la salida, procesado en su lugar por los efectos
		fxBus = Bus.audio(context.server, 1);

		// orden de ejecución: LFOs y envolventes -> voces -> filtro -> efectos -> salida
		lfoGroup = Group.new(context.xg, \addToTail);
		voiceGroup = Group.new(context.xg, \addToTail);
		filterGroup = Group.new(context.xg, \addToTail);
		fxGroup = Group.new(context.xg, \addToTail);
		outGroup = Group.new(context.xg, \addToTail);

		// un subgrupo por efecto, en el orden fijo de la cadena: así un efecto
		// que se prende más tarde cae igual en su lugar
		fxOrder = [\harm, \phaser, \vibrato, \flanger, \dist, \fold, \ring, \crush, \delay, \verb, \space];
		fxGroups = IdentityDictionary.new;
		fxOrder.do({ |name| fxGroups[name] = Group.new(fxGroup, \addToTail) });
		fxSynths = IdentityDictionary.new;
		fxParams = IdentityDictionary[
			\phaser -> [\phaserRate, 0.3, \phaserDepth, 0],
			\vibrato -> [\vibratoRate, 5, \vibratoDepth, 0],
			\flanger -> [\flangerRateHz, 0.3, \flangerTimeAmt, 0, \flangerDepth, 0],
			\dist -> [\distTone, 0.5, \distDrive, 0],
			\fold -> [\foldAmount, 0, \foldSym, 0],
			\ring -> [\ringFreq, 200, \ringMix, 0],
			\verb -> [\verbMix, 0, \verbRoom, 0.6],
			\harm -> [\harmAmount, 0],
			\space -> [\spaceAmount, 0, \beat, 0.5],
			\crush -> [\crushBits, 16, \crushRate, 44100],
			\delay -> [\delayTime, 0.3, \delayFeedback, 0]
		];

		context.server.sync;

		lfoSynths = Array.fill(3, { |i|
			Synth.new(\uma_lfo, [\out, lfoBuses[i].index], lfoGroup, \addToTail)
		});

		envSynths = Array.fill(2, { |i|
			Synth.new(\uma_env, [\out, envBuses[i].index], lfoGroup, \addToTail)
		});

		// ENV1 sigue a las notas (se re-dispara con cada nota nueva y se suelta
		// cuando no queda ninguna sostenida). ENV2 es manual: la dispara K3
		// desde la Lua con "filterEnvManual" (barrido de filtro a mano).
		lastEnvRetrig = 0;
		envNoteOn = {
			var now = SystemClock.seconds;
			if((now - lastEnvRetrig) > 0.005, {
				lastEnvRetrig = now;
				envSynths[0].set(\gate, 1, \t_retrig, 1);
			});
		};
		envNoteOff = {
			if(notes.isEmpty, { envSynths[0].set(\gate, 0) });
		};

		// estado de cada capa (voz A/B/C) del lado del lenguaje: cada nota nueva
		// se crea con estos valores; los cambios en vivo van a todo el grupo
		// de esa capa (notas sostenidas y colas)
		voiceKind = [0, 0, 0];
		voiceArgs = Array.fill(3, {
			var a = IdentityDictionary.new;
			a[\out] = mixBus.index;
			a[\voiceOn] = 1;
			[\enabledModBus, \kindModBus, \pwmModBus, \fmCarrierModBus, \fmAmountModBus,
				\octaveModBus, \harmonicModBus, \attModBus, \decModBus, \relModBus,
				\noiseAmountModBus, \noiseKindModBus, \ringOnModBus, \ringCarModBus,
				\ringModFreqModBus, \ringMixModBus, \wfOnModBus, \wfAmountModBus,
				\wfMainModBus, \wfOffsetModBus].do({ |k| a[k] = zeroBus.index });
			a
		});
		layerGroups = Array.fill(3, { Group.new(voiceGroup, \addToTail) });
		notes = IdentityDictionary.new;     // id -> [synth A, B, C] (nil si la capa está apagada)
		noteFreqs = IdentityDictionary.new; // id -> freq
		noteOrder = List.new;               // ids sostenidos, el más viejo primero
		tails = List.new;                   // synths soltados que siguen en su release

		setVoice = { |v, pairs|
			pairs.pairsDo({ |k, val| voiceArgs[v][k] = val });
			layerGroups[v].set(*pairs);
		};

		startLayer = { |v, freq|
			var syn;
			var a = voiceArgs[v];
			var full = ((a[\noiseAmount] ? 0) > 0) or: { a[\ringOn] == 1 } or: { a[\wfOn] == 1 };
			if(a[\voiceOn] == 1, {
				syn = Synth.new(this.class.voiceDefName(voiceKind[v], full),
					a.asKeyValuePairs ++ [\freq, freq, \gate, 1], layerGroups[v], \addToTail);
				syn.onFree({ tails.remove(syn) });
			});
			syn
		};

		// fast = corte rápido (robo de voz) en vez de su release normal.
		// gate negativo en EnvGen = release forzado de (-gate - 1) segundos
		// relTime (opcional) = release forzado de esa duración en segundos
		releaseNote = { |id, fast, relTime|
			var syns = notes[id];
			var g = if(relTime.notNil, { -1 - relTime }, { if(fast, -1.02, 0) });
			if(syns.notNil, {
				syns.do({ |syn| if(syn.notNil, {
					syn.set(\gate, g);
					tails.add(syn);
				}) });
				// tope de colas: las más viejas se cortan rápido (CPU de la Pi)
				while({ tails.size > 6 }, { tails.removeAt(0).set(\gate, -1.02) });
				notes.removeAt(id);
				noteFreqs.removeAt(id);
				noteOrder.remove(id);
			});
		};

		// cambio de motor: las notas nuevas usan el motor nuevo y las que están
		// sostenidas se re-disparan en esa capa con el motor nuevo (al instante)
		setKind = { |v, k|
			k = k.clip(0, this.class.voiceKinds.size - 1);
			if(k != voiceKind[v], {
				voiceKind[v] = k;
				notes.keysValuesDo({ |id, syns|
					if(syns[v].notNil, { syns[v].set(\gate, -1.05) });
					syns[v] = startLayer.value(v, noteFreqs[id]);
				});
			});
		};

		// estado del filtro del lado del lenguaje: al cambiar kind o poles se
		// crea el synth nuevo con los mismos valores y reemplaza al anterior
		filterState = (
			kind: 0, poles: 1, cutoff: 0.5, res: 0.3, modBus: zeroBus.index, modDepth: 0,
			env1Bus: envBuses[0].index, env1Amt: 0, env2Bus: envBuses[1].index, env2Amt: 0,
			keyFreq: 261.626, keyAmt: 0
		);
		filterArgKeys = [\cutoff, \res, \modBus, \modDepth, \env1Bus, \env1Amt, \env2Bus, \env2Amt, \keyFreq, \keyAmt];
		filterArgs = {
			[\in, mixBus.index, \out, fxBus.index]
			++ filterArgKeys.collect({ |k| [k, filterState[k]] }).flatten
		};
		filterSynth = Synth.new(this.class.filterDefName(0, 1), filterArgs.value, filterGroup, \addToTail);

		setFilterState = { |kind, poles|
			if((kind != filterState[\kind]) or: { poles != filterState[\poles] }, {
				filterState[\kind] = kind;
				filterState[\poles] = poles;
				filterSynth = Synth.new(this.class.filterDefName(kind, poles), filterArgs.value, filterSynth, \addReplace);
			});
		};

		// los efectos procesan fxBus en su lugar; la salida lo copia a la real
		outSynth = Synth.new(\uma_out, [\in, fxBus.index, \out, context.out_b.index], outGroup, \addToTail);

		// prender crea el synth (con los últimos parámetros), apagar le baja
		// el gate (se libera solo tras el fundido). Si ya estaba en ese estado
		// no hace nada: la Lua reenvía el on/off en cada movimiento de encoder
		setFxOn = { |name, on|
			var current = fxSynths[name];
			if(on == 1, {
				if(current.isNil, {
					fxSynths[name] = Synth.new(("uma_fx_" ++ name).asSymbol,
						[\bus, fxBus.index] ++ fxParams[name], fxGroups[name], \addToTail);
				});
			}, {
				if(current.notNil, {
					current.set(\gate, 0);
					fxSynths[name] = nil;
				});
			});
		};

		setFxParams = { |name, pairs|
			var params = fxParams[name];
			pairs.pairsDo({ |key, val|
				var i = params.indexOf(key);
				params[i + 1] = val;
			});
			if(fxSynths[name].notNil, { fxSynths[name].set(*pairs) });
		};

		// ---- comandos OSC ----

		// ---- notas (polifónicas): id = número que elige la Lua (la nota MIDI) ----
		this.addCommand("noteOn", "if", { arg msg;
			var id = msg[1].asInteger, freq = msg[2].asFloat;
			if(notes[id].notNil, { releaseNote.value(id, true) });
			while({ noteOrder.size >= 6 }, { releaseNote.value(noteOrder[0], true) });
			notes[id] = Array.fill(3, { |v| startLayer.value(v, freq) });
			noteFreqs[id] = freq;
			noteOrder.add(id);
			envNoteOn.value;
		});

		// nota en UNA sola voz (1-3), para el secuenciador de anillos. Usa el
		// mismo registro de notas que noteOn: noteOff / noteOffTime /
		// noteLegato funcionan igual con estos ids
		this.addCommand("noteOnVoice", "iif", { arg msg;
			var id = msg[1].asInteger, v = msg[2].asInteger - 1, freq = msg[3].asFloat;
			if(notes[id].notNil, { releaseNote.value(id, true) });
			while({ noteOrder.size >= 6 }, { releaseNote.value(noteOrder[0], true) });
			notes[id] = Array.fill(3, { |i| if(i == v, { startLayer.value(i, freq) }, { nil }) });
			noteFreqs[id] = freq;
			noteOrder.add(id);
			envNoteOn.value;
		});

		// como noteOnVoice, pero a un volumen fijo (amp) en vez del volumen de la
		// voz: el secuenciador de anillos lo usa para que los tres suenen parejo.
		// Respeta el on/off de la voz. Solo lo usa el secuenciador
		this.addCommand("noteOnVoiceAmp", "iiff", { arg msg;
			var id = msg[1].asInteger, v = msg[2].asInteger - 1, freq = msg[3].asFloat, amp = msg[4].asFloat;
			if(notes[id].notNil, { releaseNote.value(id, true) });
			while({ noteOrder.size >= 6 }, { releaseNote.value(noteOrder[0], true) });
			notes[id] = Array.fill(3, { |i|
				var syn, a = voiceArgs[i];
				var full = ((a[\noiseAmount] ? 0) > 0) or: { a[\ringOn] == 1 } or: { a[\wfOn] == 1 };
				if((i == v) and: { a[\voiceOn] == 1 }, {
					syn = Synth.new(this.class.voiceDefName(voiceKind[i], full),
						a.asKeyValuePairs ++ [\freq, freq, \gate, 1, \amp, amp], layerGroups[i], \addToTail);
					syn.onFree({ tails.remove(syn) });
				});
				syn
			});
			noteFreqs[id] = freq;
			noteOrder.add(id);
			envNoteOn.value;
		});

		this.addCommand("noteOff", "i", { arg msg;
			releaseNote.value(msg[1].asInteger, false);
			envNoteOff.value;
		});

		// suelta una nota con un release corto propio (pasos del arp: el gate
		// define cuánto suena cada paso, sin que la cola del preset lo tape)
		this.addCommand("noteOffTime", "if", { arg msg;
			releaseNote.value(msg[1].asInteger, false, msg[2].asFloat.max(0.005));
			envNoteOff.value;
		});

		// cambia la altura de una nota sostenida sin re-disparar (slide del arp)
		this.addCommand("noteLegato", "if", { arg msg;
			var id = msg[1].asInteger, syns = notes[id];
			if(syns.notNil, {
				noteFreqs[id] = msg[2].asFloat;
				syns.do({ |syn| if(syn.notNil, { syn.set(\freq, msg[2].asFloat) }) });
			});
		});

		// legato del arp: cambia la altura sin cortar y re-enciende la
		// envolvente desde donde está, así ninguna capa se apaga por su sustain
		this.addCommand("noteRestrike", "if", { arg msg;
			var id = msg[1].asInteger, syns = notes[id];
			if(syns.notNil, {
				noteFreqs[id] = msg[2].asFloat;
				syns.do({ |syn| if(syn.notNil, { syn.set(\freq, msg[2].asFloat, \t_retrig, 1) }) });
			});
		});

		this.addCommand("allNotesOff", "", { arg msg;
			noteOrder.copy.do({ |id| releaseNote.value(id, false) });
			envNoteOff.value;
		});

		this.addCommand("kind", "if", { arg msg;
			setKind.value(msg[1].asInteger - 1, msg[2].asFloat.round.asInteger);
		});

		// multiplicador de octava por capa (2 ** octava)
		this.addCommand("octMul", "if", { arg msg;
			setVoice.value(msg[1].asInteger - 1, [\octMul, msg[2].asFloat]);
		});

		// ENV2 manual (K3 en la página 1): 1 = dispara y sostiene, 0 = suelta
		this.addCommand("filterEnvManual", "i", { arg msg;
			var g = msg[1].asInteger;
			envSynths[1].set(\gate, g, \t_retrig, g);
		});

		this.addCommand("fxSpaceOn", "i", { arg msg;
			setFxOn.value(\space, msg[1].asInteger);
		});

		this.addCommand("fxSpace", "ff", { arg msg;
			setFxParams.value(\space, [\spaceAmount, msg[1].asFloat, \beat, msg[2].asFloat]);
		});

		this.addCommand("fxHarmOn", "i", { arg msg;
			setFxOn.value(\harm, msg[1].asInteger);
		});

		this.addCommand("fxHarm", "f", { arg msg;
			setFxParams.value(\harm, [\harmAmount, msg[1].asFloat]);
		});

		this.addCommand("fxVerbOn", "i", { arg msg;
			setFxOn.value(\verb, msg[1].asInteger);
		});

		this.addCommand("fxVerb", "ff", { arg msg;
			setFxParams.value(\verb, [\verbMix, msg[1].asFloat, \verbRoom, msg[2].asFloat]);
		});

		this.addCommand("fxRingOn", "i", { arg msg;
			setFxOn.value(\ring, msg[1].asInteger);
		});

		this.addCommand("fxRing", "ff", { arg msg;
			setFxParams.value(\ring, [\ringFreq, msg[1].asFloat, \ringMix, msg[2].asFloat]);
		});

		this.addCommand("fxFoldOn", "i", { arg msg;
			setFxOn.value(\fold, msg[1].asInteger);
		});

		this.addCommand("fxFold", "ff", { arg msg;
			setFxParams.value(\fold, [\foldAmount, msg[1].asFloat, \foldSym, msg[2].asFloat]);
		});

		this.addCommand("pwm", "if", { arg msg;
			setVoice.value(msg[1].asInteger - 1, [\pwm, msg[2].asFloat]);
		});

		this.addCommand("fm", "iff", { arg msg;
			setVoice.value(msg[1].asInteger - 1, [\fmCarrier, msg[2].asFloat, \fmAmount, msg[3].asFloat]);
		});

		this.addCommand("noiseKind", "if", { arg msg;
			setVoice.value(msg[1].asInteger - 1, [\noiseKind, msg[2].asFloat]);
		});

		this.addCommand("noiseAmount", "if", { arg msg;
			setVoice.value(msg[1].asInteger - 1, [\noiseAmount, msg[2].asFloat]);
		});

		this.addCommand("adr", "ifff", { arg msg;
			setVoice.value(msg[1].asInteger - 1, [
				\att, msg[2].asFloat, \dec, msg[3].asFloat, \rel, msg[4].asFloat
			]);
		});

		// nivel al que decae la envolvente mientras se sostiene la nota
		// (1 = sin decay audible, el comportamiento original)
		this.addCommand("sustain", "if", { arg msg;
			setVoice.value(msg[1].asInteger - 1, [\sus, msg[2].asFloat]);
		});

		this.addCommand("ringMod", "ifff", { arg msg;
			setVoice.value(msg[1].asInteger - 1, [
				\ringCarRatio, msg[2].asFloat, \ringModFreq, msg[3].asFloat, \ringMix, msg[4].asFloat
			]);
		});

		this.addCommand("ringOn", "ii", { arg msg;
			setVoice.value(msg[1].asInteger - 1, [\ringOn, msg[2].asInteger]);
		});

		this.addCommand("waveFolder", "ifff", { arg msg;
			setVoice.value(msg[1].asInteger - 1, [
				\wfAmount, msg[2].asFloat, \wfMain, msg[3].asFloat, \wfOffset, msg[4].asFloat
			]);
		});

		this.addCommand("wfOn", "ii", { arg msg;
			setVoice.value(msg[1].asInteger - 1, [\wfOn, msg[2].asInteger]);
		});

		this.addCommand("voiceOn", "ii", { arg msg;
			setVoice.value(msg[1].asInteger - 1, [\voiceOn, msg[2].asInteger]);
		});

		this.addCommand("amp", "if", { arg msg;
			setVoice.value(msg[1].asInteger - 1, [\amp, msg[2].asFloat]);
		});

		this.addCommand("lfoShape", "ii", { arg msg;
			lfoSynths[msg[1].asInteger - 1].set(\shape, msg[2].asInteger);
		});

		this.addCommand("lfoRate", "if", { arg msg;
			lfoSynths[msg[1].asInteger - 1].set(\rate, msg[2].asFloat);
		});

		this.addCommand("filterKind", "i", { arg msg;
			setFilterState.value(msg[1].asInteger.clip(0, 3), filterState[\poles]);
		});

		this.addCommand("filterPoles", "i", { arg msg;
			setFilterState.value(filterState[\kind], msg[1].asInteger.clip(1, 4));
		});

		this.addCommand("filterCutoff", "f", { arg msg;
			filterState[\cutoff] = msg[1].asFloat;
			filterSynth.set(\cutoff, filterState[\cutoff]);
		});

		this.addCommand("filterRes", "f", { arg msg;
			filterState[\res] = msg[1].asFloat;
			filterSynth.set(\res, filterState[\res]);
		});

		this.addCommand("filterMod", "if", { arg msg;
			var lfoIdx = msg[1].asInteger;
			filterState[\modBus] = if(lfoIdx == 0, { zeroBus.index }, { lfoBuses[lfoIdx - 1].index });
			filterState[\modDepth] = msg[2].asFloat;
			filterSynth.set(\modBus, filterState[\modBus], \modDepth, filterState[\modDepth]);
		});

		// ---- envolventes de filtro (índice 1-2) ----

		this.addCommand("envAdsr", "iffff", { arg msg;
			envSynths[msg[1].asInteger - 1].set(
				\att, msg[2].asFloat, \dec, msg[3].asFloat, \sus, msg[4].asFloat, \rel, msg[5].asFloat
			);
		});

		// cuánto mueve esa envolvente el cutoff: -1..1 sobre el rango 0-1
		this.addCommand("envFilter", "if", { arg msg;
			var key = [\env1Amt, \env2Amt][msg[1].asInteger - 1];
			filterState[key] = msg[2].asFloat;
			filterSynth.set(key, filterState[key]);
		});

		// keytrack del filtro: 0 = fijo, 1 = una octava de corte por octava de nota
		this.addCommand("filterKeyTrack", "f", { arg msg;
			filterState[\keyAmt] = msg[1].asFloat;
			filterSynth.set(\keyAmt, filterState[\keyAmt]);
		});

		// nota de teclado actual (Hz, sin la octava propia de cada NCO)
		this.addCommand("filterKey", "f", { arg msg;
			filterState[\keyFreq] = msg[1].asFloat;
			filterSynth.set(\keyFreq, filterState[\keyFreq]);
		});

		// ---- effects ----

		this.addCommand("fxPhaserOn", "i", { arg msg;
			setFxOn.value(\phaser, msg[1].asInteger);
		});

		this.addCommand("fxPhaser", "ff", { arg msg;
			setFxParams.value(\phaser, [\phaserRate, msg[1].asFloat, \phaserDepth, msg[2].asFloat]);
		});

		this.addCommand("fxVibratoOn", "i", { arg msg;
			setFxOn.value(\vibrato, msg[1].asInteger);
		});

		this.addCommand("fxVibrato", "ff", { arg msg;
			setFxParams.value(\vibrato, [\vibratoRate, msg[1].asFloat, \vibratoDepth, msg[2].asFloat]);
		});

		this.addCommand("fxFlangerOn", "i", { arg msg;
			setFxOn.value(\flanger, msg[1].asInteger);
		});

		this.addCommand("fxFlanger", "fff", { arg msg;
			setFxParams.value(\flanger, [\flangerRateHz, msg[1].asFloat, \flangerTimeAmt, msg[2].asFloat, \flangerDepth, msg[3].asFloat]);
		});

		this.addCommand("fxDistortionOn", "i", { arg msg;
			setFxOn.value(\dist, msg[1].asInteger);
		});

		this.addCommand("fxDistortion", "ff", { arg msg;
			setFxParams.value(\dist, [\distTone, msg[1].asFloat, \distDrive, msg[2].asFloat]);
		});

		this.addCommand("fxBitcrushOn", "i", { arg msg;
			setFxOn.value(\crush, msg[1].asInteger);
		});

		this.addCommand("fxBitcrush", "ff", { arg msg;
			setFxParams.value(\crush, [\crushBits, msg[1].asFloat, \crushRate, msg[2].asFloat]);
		});

		this.addCommand("fxDelayOn", "i", { arg msg;
			setFxOn.value(\delay, msg[1].asInteger);
		});

		this.addCommand("fxDelay", "ff", { arg msg;
			setFxParams.value(\delay, [\delayTime, msg[1].asFloat, \delayFeedback, msg[2].asFloat]);
		});

		// ---- asignación genérica de modulación: voz, índice de LFO
		// (0=apagado, 1-3), amount 0-1, por cada destino modulable ----

		addModCmd = { |name, busArg, amtArg|
			this.addCommand(name, "iif", { arg msg;
				var v = msg[1].asInteger - 1;
				var lfoIdx = msg[2].asInteger;
				var bus = if(lfoIdx == 0, { zeroBus.index }, { lfoBuses[lfoIdx - 1].index });
				setVoice.value(v, [busArg, bus, amtArg, msg[3].asFloat]);
			});
		};

		addModCmd.value("modEnabled", \enabledModBus, \enabledModAmt);
		addModCmd.value("modKind", \kindModBus, \kindModAmt);
		addModCmd.value("modPwm", \pwmModBus, \pwmModAmt);
		addModCmd.value("modFmCarrier", \fmCarrierModBus, \fmCarrierModAmt);
		addModCmd.value("modFmAmount", \fmAmountModBus, \fmAmountModAmt);
		addModCmd.value("modOctave", \octaveModBus, \octaveModAmt);
		addModCmd.value("modHarmonic", \harmonicModBus, \harmonicModAmt);
		addModCmd.value("modAttack", \attModBus, \attModAmt);
		addModCmd.value("modDecay", \decModBus, \decModAmt);
		addModCmd.value("modRelease", \relModBus, \relModAmt);
		addModCmd.value("modNoiseAmount", \noiseAmountModBus, \noiseAmountModAmt);
		addModCmd.value("modNoiseKind", \noiseKindModBus, \noiseKindModAmt);
		addModCmd.value("modRingOn", \ringOnModBus, \ringOnModAmt);
		addModCmd.value("modRingCar", \ringCarModBus, \ringCarModAmt);
		addModCmd.value("modRingModFreq", \ringModFreqModBus, \ringModFreqModAmt);
		addModCmd.value("modRingMix", \ringMixModBus, \ringMixModAmt);
		addModCmd.value("modWfOn", \wfOnModBus, \wfOnModAmt);
		addModCmd.value("modWfAmount", \wfAmountModBus, \wfAmountModAmt);
		addModCmd.value("modWfMain", \wfMainModBus, \wfMainModAmt);
		addModCmd.value("modWfOffset", \wfOffsetModBus, \wfOffsetModAmt);
	}

	free {
		// liberar los grupos libera todos los synths de adentro
		[lfoGroup, voiceGroup, filterGroup, fxGroup, outGroup].do({ |g| g.free });
		([zeroBus, mixBus, fxBus] ++ lfoBuses ++ envBuses).do({ |b| b.free });
	}
}
