-- Анимации бойцов (генерирует tools/clips.py — правки делать там).
return {
	["FightIdle"] = {
		Length = 2.0,
		Loop = true,
		Keys = {
			{ t = 0.0, ease = "smooth", pose = { root = { yaw = 30.0, pitch = 4.0, y = -0.01 }, waist = { pitch = 10.0, yaw = -12.0 }, head = { yaw = -18.0, pitch = 4.0 }, armR = { pitch = 38.0, out = 16.0, twist = -20.0 }, elbowR = { bend = 118.0 }, armL = { pitch = 62.0, out = -4.0, twist = -10.0 }, elbowL = { bend = 75.0 }, legR = { pitch = -22.0, out = 12.0 }, kneeR = { bend = 32.0 }, legL = { pitch = 30.0, out = 8.0 }, kneeL = { bend = 38.0 } } },
			{ t = 1.0, ease = "smooth", pose = { root = { yaw = 30.0, pitch = 4.0, y = -0.03 }, waist = { pitch = 14.0, yaw = -12.0 }, head = { yaw = -18.0, pitch = 4.0 }, armR = { pitch = 42.0, out = 16.0, twist = -20.0 }, elbowR = { bend = 118.0 }, armL = { pitch = 66.0, out = -4.0, twist = -10.0 }, elbowL = { bend = 75.0 }, legR = { pitch = -18.0, out = 12.0 }, kneeR = { bend = 44.0 }, legL = { pitch = 36.0, out = 8.0 }, kneeL = { bend = 52.0 } } },
			{ t = 2.0, ease = "smooth", pose = { root = { yaw = 30.0, pitch = 4.0, y = -0.01 }, waist = { pitch = 10.0, yaw = -12.0 }, head = { yaw = -18.0, pitch = 4.0 }, armR = { pitch = 38.0, out = 16.0, twist = -20.0 }, elbowR = { bend = 118.0 }, armL = { pitch = 62.0, out = -4.0, twist = -10.0 }, elbowL = { bend = 75.0 }, legR = { pitch = -22.0, out = 12.0 }, kneeR = { bend = 32.0 }, legL = { pitch = 30.0, out = 8.0 }, kneeL = { bend = 38.0 } } },
		},
		Markers = {
		},
	},
	["Dodge"] = {
		Length = 0.6,
		Loop = false,
		Keys = {
			{ t = 0.0, ease = "smooth", pose = { root = { yaw = 30.0, pitch = 4.0, y = -0.01 }, waist = { pitch = 10.0, yaw = -12.0 }, head = { yaw = -18.0, pitch = 4.0 }, armR = { pitch = 38.0, out = 16.0, twist = -20.0 }, elbowR = { bend = 118.0 }, armL = { pitch = 62.0, out = -4.0, twist = -10.0 }, elbowL = { bend = 75.0 }, legR = { pitch = -22.0, out = 12.0 }, kneeR = { bend = 32.0 }, legL = { pitch = 30.0, out = 8.0 }, kneeL = { bend = 38.0 } } },
			{ t = 0.12, ease = "out", pose = { root = { pitch = 10.0, y = -0.843 }, waist = { pitch = 30.0 }, head = { pitch = -15.0 }, armR = { pitch = -30.0, out = 28.0 }, elbowR = { bend = 30.0 }, armL = { pitch = -30.0, out = 28.0 }, elbowL = { bend = 30.0 }, legR = { pitch = 70.0, out = 14.0 }, kneeR = { bend = 130.0 }, legL = { pitch = 70.0, out = 14.0 }, kneeL = { bend = 130.0 } } },
			{ t = 0.34, ease = "snap", pose = { root = { yaw = 24.0, pitch = 6.0, y = -0.627 }, waist = { pitch = 24.0, yaw = -8.0 }, head = { yaw = -14.0, pitch = -14.0 }, armR = { pitch = 72.0, out = 8.0, twist = -18.0 }, elbowR = { bend = 60.0 }, armL = { pitch = -28.0, out = 36.0 }, elbowL = { bend = 40.0 }, legR = { pitch = -30.0, out = 18.0 }, kneeR = { bend = 95.0 }, legL = { pitch = 72.0, out = 10.0 }, kneeL = { bend = 110.0 } } },
			{ t = 0.6, ease = "out", pose = { root = { yaw = 24.0, pitch = 6.0, y = -0.627 }, waist = { pitch = 20.0, yaw = -8.0 }, head = { yaw = -14.0, pitch = -14.0 }, armR = { pitch = 72.0, out = 8.0, twist = -18.0 }, elbowR = { bend = 55.0 }, armL = { pitch = -28.0, out = 36.0 }, elbowL = { bend = 40.0 }, legR = { pitch = -30.0, out = 18.0 }, kneeR = { bend = 95.0 }, legL = { pitch = 72.0, out = 10.0 }, kneeL = { bend = 110.0 } } },
		},
		Markers = {
			{ t = 0.12, name = "vanish" },
			{ t = 0.32, name = "appear" },
		},
	},
	["HandSeal"] = {
		Length = 0.6,
		Loop = false,
		Keys = {
			{ t = 0.0, ease = "smooth", pose = { root = { yaw = 30.0, pitch = 4.0, y = -0.01 }, waist = { pitch = 10.0, yaw = -12.0 }, head = { yaw = -18.0, pitch = 4.0 }, armR = { pitch = 38.0, out = 16.0, twist = -20.0 }, elbowR = { bend = 118.0 }, armL = { pitch = 62.0, out = -4.0, twist = -10.0 }, elbowL = { bend = 75.0 }, legR = { pitch = -22.0, out = 12.0 }, kneeR = { bend = 32.0 }, legL = { pitch = 30.0, out = 8.0 }, kneeL = { bend = 38.0 } } },
			{ t = 0.12, ease = "snap", pose = { root = { pitch = 2.0, y = 0.18 }, waist = { pitch = 6.0 }, head = { pitch = 6.0 }, armR = { pitch = 62.0, out = -22.0, twist = 0.0 }, elbowR = { bend = 88.0 }, armL = { pitch = 62.0, out = -22.0, twist = 0.0 }, elbowL = { bend = 88.0 }, legR = { pitch = -6.0, out = 10.0 }, kneeR = { bend = 18.0 }, legL = { pitch = 10.0, out = 10.0 }, kneeL = { bend = 20.0 } } },
			{ t = 0.38, ease = "smooth", pose = { root = { pitch = 2.0, y = 0.173 }, waist = { pitch = 9.0 }, head = { pitch = 6.0 }, armR = { pitch = 62.0, out = -22.0, twist = 0.0 }, elbowR = { bend = 88.0 }, armL = { pitch = 62.0, out = -22.0, twist = 0.0 }, elbowL = { bend = 88.0 }, legR = { pitch = -6.0, out = 10.0 }, kneeR = { bend = 24.0 }, legL = { pitch = 10.0, out = 10.0 }, kneeL = { bend = 26.0 } } },
			{ t = 0.47, ease = "snap", pose = { root = { yaw = -20.0, pitch = 6.0, y = 0.042 }, waist = { pitch = 8.0, yaw = 6.0 }, head = { yaw = 14.0, pitch = 2.0 }, armR = { pitch = 92.0, out = -6.0 }, elbowR = { bend = 4.0 }, armL = { pitch = 12.0, out = 12.0 }, elbowL = { bend = 60.0 }, legR = { pitch = -24.0, out = 12.0 }, kneeR = { bend = 30.0 }, legL = { pitch = 30.0, out = 8.0 }, kneeL = { bend = 36.0 } } },
			{ t = 0.6, ease = "out", pose = { root = { yaw = -20.0, pitch = 6.0, y = 0.042 }, waist = { pitch = 8.0, yaw = 6.0 }, head = { yaw = 14.0, pitch = 2.0 }, armR = { pitch = 90.0, out = -6.0 }, elbowR = { bend = 4.0 }, armL = { pitch = 12.0, out = 12.0 }, elbowL = { bend = 60.0 }, legR = { pitch = -24.0, out = 12.0 }, kneeR = { bend = 30.0 }, legL = { pitch = 30.0, out = 8.0 }, kneeL = { bend = 36.0 } } },
		},
		Markers = {
			{ t = 0.12, name = "seal" },
			{ t = 0.47, name = "point" },
		},
	},
	["CloneKickUp"] = {
		Length = 0.5,
		Loop = false,
		Keys = {
			{ t = 0.0, ease = "smooth", pose = { root = { pitch = -58.0, y = -2.25 }, waist = { pitch = 18.0 }, head = { pitch = 28.0 }, armR = { pitch = -35.0, out = 42.0 }, elbowR = { bend = 10.0 }, armL = { pitch = -35.0, out = 42.0 }, elbowL = { bend = 10.0 }, legR = { pitch = 8.0, out = 4.0 }, kneeR = { bend = 20.0 }, legL = { pitch = -4.0, out = 10.0 }, kneeL = { bend = 70.0 } } },
			{ t = 0.18, ease = "smooth", pose = { root = { pitch = -66.0, y = -2.25 }, waist = { pitch = 18.0 }, head = { pitch = 28.0 }, armR = { pitch = -35.0, out = 42.0 }, elbowR = { bend = 10.0 }, armL = { pitch = -35.0, out = 42.0 }, elbowL = { bend = 10.0 }, legR = { pitch = 40.0, out = 4.0 }, kneeR = { bend = 110.0 }, legL = { pitch = -4.0, out = 10.0 }, kneeL = { bend = 70.0 } } },
			{ t = 0.26, ease = "snap", pose = { root = { pitch = -82.0, y = -2.25 }, waist = { pitch = 24.0 }, head = { pitch = 38.0 }, armR = { pitch = -50.0, out = 52.0 }, elbowR = { bend = 6.0 }, armL = { pitch = -50.0, out = 52.0 }, elbowL = { bend = 6.0 }, legR = { pitch = 100.0, out = 0.0 }, kneeR = { bend = 0.0 }, legL = { pitch = -4.0, out = 12.0 }, kneeL = { bend = 80.0 } } },
			{ t = 0.5, ease = "out", pose = { root = { pitch = -82.0, y = -2.25 }, waist = { pitch = 24.0 }, head = { pitch = 38.0 }, armR = { pitch = -50.0, out = 52.0 }, elbowR = { bend = 6.0 }, armL = { pitch = -50.0, out = 52.0 }, elbowL = { bend = 6.0 }, legR = { pitch = 92.0, out = 0.0 }, kneeR = { bend = 10.0 }, legL = { pitch = -4.0, out = 12.0 }, kneeL = { bend = 80.0 } } },
		},
		Markers = {
			{ t = 0.26, name = "hit" },
		},
	},
	["HeelDrop"] = {
		Length = 1.2,
		Loop = false,
		Keys = {
			{ t = 0.0, ease = "smooth", pose = { root = { pitch = 10.0, y = -0.843 }, waist = { pitch = 30.0 }, head = { pitch = -15.0 }, armR = { pitch = -30.0, out = 28.0 }, elbowR = { bend = 30.0 }, armL = { pitch = -30.0, out = 28.0 }, elbowL = { bend = 30.0 }, legR = { pitch = 70.0, out = 14.0 }, kneeR = { bend = 130.0 }, legL = { pitch = 70.0, out = 14.0 }, kneeL = { bend = 130.0 } } },
			{ t = 0.18, ease = "out", pose = { root = { y = 0.5, pitch = -8.0 }, waist = { pitch = -10.0 }, head = { pitch = -20.0 }, armR = { pitch = 168.0, out = 14.0 }, elbowR = { bend = 10.0 }, armL = { pitch = 168.0, out = 14.0 }, elbowL = { bend = 10.0 }, legR = { pitch = -12.0, out = 4.0 }, kneeR = { bend = 20.0 }, legL = { pitch = -8.0, out = 4.0 }, kneeL = { bend = 30.0 } } },
			{ t = 0.42, ease = "smooth", pose = { root = { y = 0.8, pitch = 200.0 }, waist = { pitch = 40.0 }, head = { pitch = 30.0 }, armR = { pitch = 30.0, out = 20.0 }, elbowR = { bend = 90.0 }, armL = { pitch = 30.0, out = 20.0 }, elbowL = { bend = 90.0 }, legR = { pitch = 110.0 }, kneeR = { bend = 120.0 }, legL = { pitch = 110.0 }, kneeL = { bend = 120.0 } } },
			{ t = 0.6, ease = "out", pose = { root = { y = 0.8, pitch = 352.0 }, waist = { pitch = -6.0 }, head = { pitch = -18.0 }, armR = { pitch = 40.0, out = 72.0 }, elbowR = { bend = 20.0 }, armL = { pitch = 40.0, out = 72.0 }, elbowL = { bend = 20.0 }, legR = { pitch = 174.0, out = 0.0 }, kneeR = { bend = 4.0 }, legL = { pitch = -24.0, out = 8.0 }, kneeL = { bend = 40.0 } } },
			{ t = 0.601, ease = "linear", pose = { root = { y = 0.8, pitch = -8.0 }, waist = { pitch = -6.0 }, head = { pitch = -18.0 }, armR = { pitch = 40.0, out = 72.0 }, elbowR = { bend = 20.0 }, armL = { pitch = 40.0, out = 72.0 }, elbowL = { bend = 20.0 }, legR = { pitch = 174.0, out = 0.0 }, kneeR = { bend = 4.0 }, legL = { pitch = -24.0, out = 8.0 }, kneeL = { bend = 40.0 } } },
			{ t = 0.72, ease = "snap", pose = { root = { y = 0.2, pitch = 8.0 }, waist = { pitch = 16.0 }, head = { pitch = -24.0 }, armR = { pitch = -35.0, out = 60.0 }, elbowR = { bend = 20.0 }, armL = { pitch = -35.0, out = 60.0 }, elbowL = { bend = 20.0 }, legR = { pitch = -6.0, out = 0.0 }, kneeR = { bend = 0.0 }, legL = { pitch = -30.0, out = 8.0 }, kneeL = { bend = 50.0 } } },
			{ t = 0.95, ease = "out", pose = { root = { pitch = 14.0, y = -0.904 }, waist = { pitch = 30.0 }, head = { pitch = -15.0 }, armR = { pitch = -20.0, out = 70.0 }, elbowR = { bend = 30.0 }, armL = { pitch = -20.0, out = 70.0 }, elbowL = { bend = 30.0 }, legR = { pitch = 60.0, out = 14.0 }, kneeR = { bend = 130.0 }, legL = { pitch = 20.0, out = 14.0 }, kneeL = { bend = 150.0 } } },
			{ t = 1.2, ease = "smooth", pose = { root = { yaw = 30.0, pitch = 4.0, y = -0.01 }, waist = { pitch = 10.0, yaw = -12.0 }, head = { yaw = -18.0, pitch = 4.0 }, armR = { pitch = 38.0, out = 16.0, twist = -20.0 }, elbowR = { bend = 118.0 }, armL = { pitch = 62.0, out = -4.0, twist = -10.0 }, elbowL = { bend = 75.0 }, legR = { pitch = -22.0, out = 12.0 }, kneeR = { bend = 32.0 }, legL = { pitch = 30.0, out = 8.0 }, kneeL = { bend = 38.0 } } },
		},
		Markers = {
			{ t = 0.18, name = "jump" },
			{ t = 0.72, name = "hit" },
			{ t = 0.95, name = "land" },
		},
	},
	["CloneRushPunch"] = {
		Length = 0.45,
		Loop = false,
		Keys = {
			{ t = 0.0, ease = "smooth", pose = { root = { yaw = 30.0, pitch = 4.0, y = -0.01 }, waist = { pitch = 10.0, yaw = -12.0 }, head = { yaw = -18.0, pitch = 4.0 }, armR = { pitch = 38.0, out = 16.0, twist = -20.0 }, elbowR = { bend = 118.0 }, armL = { pitch = 62.0, out = -4.0, twist = -10.0 }, elbowL = { bend = 75.0 }, legR = { pitch = -22.0, out = 12.0 }, kneeR = { bend = 32.0 }, legL = { pitch = 30.0, out = 8.0 }, kneeL = { bend = 38.0 } } },
			{ t = 0.1, ease = "smooth", pose = { root = { yaw = 44.0, pitch = 4.0, y = -0.028 }, waist = { pitch = 10.0, yaw = 10.0 }, head = { yaw = -18.0, pitch = 4.0 }, armR = { pitch = 20.0, out = 12.0, twist = -20.0 }, elbowR = { bend = 130.0 }, armL = { pitch = 62.0, out = -4.0, twist = -10.0 }, elbowL = { bend = 75.0 }, legR = { pitch = -22.0, out = 12.0 }, kneeR = { bend = 32.0 }, legL = { pitch = 30.0, out = 8.0 }, kneeL = { bend = 38.0 } } },
			{ t = 0.17, ease = "snap", pose = { root = { yaw = -28.0, pitch = 10.0, y = -0.084 }, waist = { pitch = 14.0, yaw = -14.0 }, head = { yaw = 24.0 }, armR = { pitch = 92.0, out = -6.0 }, elbowR = { bend = 2.0 }, armL = { pitch = 34.0, out = 12.0 }, elbowL = { bend = 120.0 }, legR = { pitch = -40.0, out = 10.0 }, kneeR = { bend = 20.0 }, legL = { pitch = 46.0, out = 8.0 }, kneeL = { bend = 50.0 } } },
			{ t = 0.45, ease = "out", pose = { root = { yaw = -28.0, pitch = 10.0, y = -0.084 }, waist = { pitch = 14.0, yaw = -14.0 }, head = { yaw = 24.0 }, armR = { pitch = 86.0, out = -6.0 }, elbowR = { bend = 14.0 }, armL = { pitch = 34.0, out = 12.0 }, elbowL = { bend = 120.0 }, legR = { pitch = -40.0, out = 10.0 }, kneeR = { bend = 20.0 }, legL = { pitch = 46.0, out = 8.0 }, kneeL = { bend = 50.0 } } },
		},
		Markers = {
			{ t = 0.17, name = "hit" },
		},
	},
	["CloneSpinKick"] = {
		Length = 0.5,
		Loop = false,
		Keys = {
			{ t = 0.0, ease = "smooth", pose = { root = { yaw = 30.0, pitch = 4.0, y = -0.01 }, waist = { pitch = 10.0, yaw = -12.0 }, head = { yaw = -18.0, pitch = 4.0 }, armR = { pitch = 38.0, out = 16.0, twist = -20.0 }, elbowR = { bend = 118.0 }, armL = { pitch = 62.0, out = -4.0, twist = -10.0 }, elbowL = { bend = 75.0 }, legR = { pitch = -22.0, out = 12.0 }, kneeR = { bend = 32.0 }, legL = { pitch = 30.0, out = 8.0 }, kneeL = { bend = 38.0 } } },
			{ t = 0.14, ease = "smooth", pose = { root = { yaw = 170.0, pitch = 4.0, y = -0.143 }, waist = { pitch = 10.0, yaw = -12.0 }, head = { yaw = -18.0, pitch = 4.0 }, armR = { pitch = 38.0, out = 16.0, twist = -20.0 }, elbowR = { bend = 118.0 }, armL = { pitch = 62.0, out = -4.0, twist = -10.0 }, elbowL = { bend = 75.0 }, legR = { pitch = 20.0, out = 40.0 }, kneeR = { bend = 80.0 }, legL = { pitch = 30.0, out = 8.0 }, kneeL = { bend = 38.0 } } },
			{ t = 0.24, ease = "snap", pose = { root = { pitch = -14.0, roll = -20.0, yaw = 300.0, y = -0.604 }, waist = { pitch = -6.0 }, head = { yaw = -40.0 }, armR = { pitch = 10.0, out = 70.0 }, elbowR = { bend = 30.0 }, armL = { pitch = 10.0, out = 70.0 }, elbowL = { bend = 30.0 }, legR = { pitch = 18.0, out = 95.0 }, kneeR = { bend = 4.0 }, legL = { pitch = -4.0, out = 6.0 }, kneeL = { bend = 26.0 } } },
			{ t = 0.5, ease = "out", pose = { root = { yaw = 390.0, pitch = 4.0, y = -0.01 }, waist = { pitch = 10.0, yaw = -12.0 }, head = { yaw = -18.0, pitch = 4.0 }, armR = { pitch = 38.0, out = 16.0, twist = -20.0 }, elbowR = { bend = 118.0 }, armL = { pitch = 62.0, out = -4.0, twist = -10.0 }, elbowL = { bend = 75.0 }, legR = { pitch = -22.0, out = 12.0 }, kneeR = { bend = 32.0 }, legL = { pitch = 30.0, out = 8.0 }, kneeL = { bend = 38.0 } } },
		},
		Markers = {
			{ t = 0.24, name = "hit" },
		},
	},
	["CloneSweep"] = {
		Length = 0.45,
		Loop = false,
		Keys = {
			{ t = 0.0, ease = "smooth", pose = { root = { yaw = 30.0, pitch = 4.0, y = -0.01 }, waist = { pitch = 10.0, yaw = -12.0 }, head = { yaw = -18.0, pitch = 4.0 }, armR = { pitch = 38.0, out = 16.0, twist = -20.0 }, elbowR = { bend = 118.0 }, armL = { pitch = 62.0, out = -4.0, twist = -10.0 }, elbowL = { bend = 75.0 }, legR = { pitch = -22.0, out = 12.0 }, kneeR = { bend = 32.0 }, legL = { pitch = 30.0, out = 8.0 }, kneeL = { bend = 38.0 } } },
			{ t = 0.1, ease = "smooth", pose = { root = { pitch = 24.0, yaw = 40.0, y = -0.832 }, waist = { pitch = 30.0 }, head = { yaw = 0.0 }, armR = { pitch = -18.0, out = 70.0 }, elbowR = { bend = 10.0 }, armL = { pitch = 50.0, out = -6.0 }, elbowL = { bend = 40.0 }, legR = { pitch = -20.0, out = 55.0 }, kneeR = { bend = 40.0 }, legL = { pitch = 60.0, out = 10.0 }, kneeL = { bend = 135.0 } } },
			{ t = 0.22, ease = "snap", pose = { root = { pitch = 24.0, yaw = -120.0, y = -0.827 }, waist = { pitch = 30.0 }, head = { yaw = 60.0 }, armR = { pitch = -18.0, out = 70.0 }, elbowR = { bend = 10.0 }, armL = { pitch = 50.0, out = -6.0 }, elbowL = { bend = 40.0 }, legR = { pitch = 6.0, out = 92.0 }, kneeR = { bend = 4.0 }, legL = { pitch = 60.0, out = 10.0 }, kneeL = { bend = 135.0 } } },
			{ t = 0.45, ease = "out", pose = { root = { pitch = 24.0, yaw = -150.0, y = -0.949 }, waist = { pitch = 30.0 }, head = { yaw = 60.0 }, armR = { pitch = -18.0, out = 70.0 }, elbowR = { bend = 10.0 }, armL = { pitch = 50.0, out = -6.0 }, elbowL = { bend = 40.0 }, legR = { pitch = 6.0, out = 80.0 }, kneeR = { bend = 4.0 }, legL = { pitch = 60.0, out = 10.0 }, kneeL = { bend = 135.0 } } },
		},
		Markers = {
			{ t = 0.22, name = "hit" },
		},
	},
	["FinisherPunch"] = {
		Length = 0.75,
		Loop = false,
		Keys = {
			{ t = 0.0, ease = "smooth", pose = { root = { yaw = 30.0, pitch = 4.0, y = -0.01 }, waist = { pitch = 10.0, yaw = -12.0 }, head = { yaw = -18.0, pitch = 4.0 }, armR = { pitch = 38.0, out = 16.0, twist = -20.0 }, elbowR = { bend = 118.0 }, armL = { pitch = 62.0, out = -4.0, twist = -10.0 }, elbowL = { bend = 75.0 }, legR = { pitch = -22.0, out = 12.0 }, kneeR = { bend = 32.0 }, legL = { pitch = 30.0, out = 8.0 }, kneeL = { bend = 38.0 } } },
			{ t = 0.26, ease = "out", pose = { root = { yaw = 58.0, pitch = 4.0, y = -0.116 }, waist = { yaw = 24.0, pitch = 8.0 }, head = { yaw = -48.0 }, armR = { pitch = -62.0, out = 28.0, twist = -20.0 }, elbowR = { bend = 95.0 }, armL = { pitch = 82.0, out = -18.0 }, elbowL = { bend = 30.0 }, legR = { pitch = -34.0, out = 16.0 }, kneeR = { bend = 46.0 }, legL = { pitch = 38.0, out = 10.0 }, kneeL = { bend = 50.0 } } },
			{ t = 0.33, ease = "snap", pose = { root = { yaw = -42.0, pitch = 16.0, y = -0.142 }, waist = { yaw = -22.0, pitch = 18.0 }, head = { yaw = 34.0, pitch = -6.0 }, armR = { pitch = 94.0, out = -8.0 }, elbowR = { bend = 0.0 }, armL = { pitch = -30.0, out = 30.0 }, elbowL = { bend = 80.0 }, legR = { pitch = -58.0, out = 12.0 }, kneeR = { bend = 10.0 }, legL = { pitch = 60.0, out = 8.0 }, kneeL = { bend = 70.0 } } },
			{ t = 0.55, ease = "smooth", pose = { root = { yaw = -42.0, pitch = 16.0, y = -0.142 }, waist = { yaw = -22.0, pitch = 18.0 }, head = { yaw = 34.0, pitch = -6.0 }, armR = { pitch = 92.0, out = -8.0 }, elbowR = { bend = 0.0 }, armL = { pitch = -30.0, out = 30.0 }, elbowL = { bend = 80.0 }, legR = { pitch = -58.0, out = 12.0 }, kneeR = { bend = 10.0 }, legL = { pitch = 60.0, out = 8.0 }, kneeL = { bend = 70.0 } } },
			{ t = 0.75, ease = "smooth", pose = { root = { yaw = 30.0, pitch = 4.0, y = -0.01 }, waist = { pitch = 10.0, yaw = -12.0 }, head = { yaw = -18.0, pitch = 4.0 }, armR = { pitch = 38.0, out = 16.0, twist = -20.0 }, elbowR = { bend = 118.0 }, armL = { pitch = 62.0, out = -4.0, twist = -10.0 }, elbowL = { bend = 75.0 }, legR = { pitch = -22.0, out = 12.0 }, kneeR = { bend = 32.0 }, legL = { pitch = 30.0, out = 8.0 }, kneeL = { bend = 38.0 } } },
		},
		Markers = {
			{ t = 0.26, name = "charge" },
			{ t = 0.33, name = "hit" },
		},
	},
	["CloneBoost"] = {
		Length = 0.4,
		Loop = false,
		Keys = {
			{ t = 0.0, ease = "smooth", pose = { root = { yaw = 30.0, pitch = 4.0, y = -0.01 }, waist = { pitch = 10.0, yaw = -12.0 }, head = { yaw = -18.0, pitch = 4.0 }, armR = { pitch = 38.0, out = 16.0, twist = -20.0 }, elbowR = { bend = 118.0 }, armL = { pitch = 62.0, out = -4.0, twist = -10.0 }, elbowL = { bend = 75.0 }, legR = { pitch = -22.0, out = 12.0 }, kneeR = { bend = 32.0 }, legL = { pitch = 30.0, out = 8.0 }, kneeL = { bend = 38.0 } } },
			{ t = 0.2, ease = "out", pose = { root = { pitch = 62.0, y = -1.865 }, waist = { pitch = 20.0 }, head = { pitch = -30.0 }, armR = { pitch = 70.0, out = 10.0 }, elbowR = { bend = 20.0 }, armL = { pitch = 70.0, out = 10.0 }, elbowL = { bend = 20.0 }, legR = { pitch = 60.0, out = 12.0 }, kneeR = { bend = 120.0 }, legL = { pitch = 60.0, out = 12.0 }, kneeL = { bend = 120.0 } } },
			{ t = 0.4, ease = "smooth", pose = { root = { pitch = 62.0, y = -1.865 }, waist = { pitch = 20.0 }, head = { pitch = -30.0 }, armR = { pitch = 70.0, out = 10.0 }, elbowR = { bend = 20.0 }, armL = { pitch = 70.0, out = 10.0 }, elbowL = { bend = 20.0 }, legR = { pitch = 60.0, out = 12.0 }, kneeR = { bend = 120.0 }, legL = { pitch = 60.0, out = 12.0 }, kneeL = { bend = 120.0 } } },
		},
		Markers = {
		},
	},
	["Hurt"] = {
		Length = 0.3,
		Loop = false,
		Keys = {
			{ t = 0.0, ease = "snap", pose = { root = { pitch = -16.0, y = 0.082 }, waist = { pitch = -14.0 }, head = { pitch = -30.0 }, armR = { pitch = 30.0, out = 40.0 }, elbowR = { bend = 40.0 }, armL = { pitch = 30.0, out = 40.0 }, elbowL = { bend = 40.0 }, legR = { pitch = 12.0 }, kneeR = { bend = 20.0 }, legL = { pitch = -10.0 }, kneeL = { bend = 20.0 } } },
			{ t = 0.3, ease = "smooth", pose = { root = { y = 0.0 }, elbowR = { bend = 8.0 }, elbowL = { bend = 8.0 } } },
		},
		Markers = {
		},
	},
	["Launched"] = {
		Length = 0.6,
		Loop = false,
		Keys = {
			{ t = 0.0, ease = "snap", pose = { root = { pitch = -40.0 }, waist = { pitch = -20.0 }, head = { pitch = -40.0 }, armR = { pitch = 150.0, out = 30.0 }, elbowR = { bend = 40.0 }, armL = { pitch = 150.0, out = 30.0 }, elbowL = { bend = 40.0 }, legR = { pitch = 30.0 }, kneeR = { bend = 60.0 }, legL = { pitch = -20.0 }, kneeL = { bend = 40.0 } } },
			{ t = 0.6, ease = "smooth", pose = { root = { pitch = -70.0 }, waist = { pitch = -20.0 }, head = { pitch = -40.0 }, armR = { pitch = 150.0, out = 30.0 }, elbowR = { bend = 40.0 }, armL = { pitch = 120.0, out = 50.0 }, elbowL = { bend = 40.0 }, legR = { pitch = 30.0 }, kneeR = { bend = 60.0 }, legL = { pitch = 10.0 }, kneeL = { bend = 40.0 } } },
		},
		Markers = {
		},
	},
	["KnockBack"] = {
		Length = 0.6,
		Loop = false,
		Keys = {
			{ t = 0.0, ease = "snap", pose = { root = { pitch = -45.0 }, waist = { pitch = -20.0 }, head = { pitch = -35.0 }, armR = { pitch = 60.0, out = 60.0 }, elbowR = { bend = 30.0 }, armL = { pitch = 60.0, out = 60.0 }, elbowL = { bend = 30.0 }, legR = { pitch = 45.0 }, kneeR = { bend = 40.0 }, legL = { pitch = 20.0 }, kneeL = { bend = 30.0 } } },
			{ t = 0.6, ease = "smooth", pose = { root = { pitch = -80.0, y = -1.9 }, waist = { pitch = -20.0 }, head = { pitch = -35.0 }, armR = { pitch = 120.0, out = 60.0 }, elbowR = { bend = 30.0 }, armL = { pitch = 120.0, out = 60.0 }, elbowL = { bend = 30.0 }, legR = { pitch = 45.0 }, kneeR = { bend = 40.0 }, legL = { pitch = 20.0 }, kneeL = { bend = 30.0 } } },
		},
		Markers = {
		},
	},
	["Slammed"] = {
		Length = 0.5,
		Loop = false,
		Keys = {
			{ t = 0.0, ease = "snap", pose = { root = { pitch = 60.0, y = 0.0 }, head = { pitch = -25.0 }, armR = { pitch = 165.0, out = 45.0 }, elbowR = { bend = 30.0 }, armL = { pitch = 165.0, out = 45.0 }, elbowL = { bend = 30.0 }, legR = { pitch = -4.0, out = 12.0 }, kneeR = { bend = 10.0 }, legL = { pitch = -4.0, out = 12.0 }, kneeL = { bend = 20.0 } } },
			{ t = 0.12, ease = "snap", pose = { root = { pitch = 90.0, y = -2.6 }, head = { pitch = -25.0 }, armR = { pitch = 165.0, out = 45.0 }, elbowR = { bend = 30.0 }, armL = { pitch = 165.0, out = 45.0 }, elbowL = { bend = 30.0 }, legR = { pitch = -4.0, out = 12.0 }, kneeR = { bend = 10.0 }, legL = { pitch = -4.0, out = 12.0 }, kneeL = { bend = 20.0 } } },
			{ t = 0.5, ease = "smooth", pose = { root = { pitch = 90.0, y = -2.6 }, head = { pitch = -25.0 }, armR = { pitch = 165.0, out = 45.0 }, elbowR = { bend = 30.0 }, armL = { pitch = 165.0, out = 45.0 }, elbowL = { bend = 30.0 }, legR = { pitch = -4.0, out = 12.0 }, kneeR = { bend = 10.0 }, legL = { pitch = -4.0, out = 12.0 }, kneeL = { bend = 20.0 } } },
		},
		Markers = {
		},
	},
	["GetUp"] = {
		Length = 0.6,
		Loop = false,
		Keys = {
			{ t = 0.0, ease = "smooth", pose = { root = { pitch = 90.0, y = -2.6 }, head = { pitch = -25.0 }, armR = { pitch = 165.0, out = 45.0 }, elbowR = { bend = 30.0 }, armL = { pitch = 165.0, out = 45.0 }, elbowL = { bend = 30.0 }, legR = { pitch = -4.0, out = 12.0 }, kneeR = { bend = 10.0 }, legL = { pitch = -4.0, out = 12.0 }, kneeL = { bend = 20.0 } } },
			{ t = 0.3, ease = "smooth", pose = { root = { pitch = 30.0, y = -1.06 }, waist = { pitch = 30.0 }, head = { pitch = -15.0 }, armR = { pitch = -30.0, out = 28.0 }, elbowR = { bend = 30.0 }, armL = { pitch = -30.0, out = 28.0 }, elbowL = { bend = 30.0 }, legR = { pitch = 70.0, out = 14.0 }, kneeR = { bend = 130.0 }, legL = { pitch = 70.0, out = 14.0 }, kneeL = { bend = 130.0 } } },
			{ t = 0.6, ease = "smooth", pose = { root = { y = 0.0 }, elbowR = { bend = 8.0 }, elbowL = { bend = 8.0 } } },
		},
		Markers = {
		},
	},
}
