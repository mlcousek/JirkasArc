// TrainingKey.swift
//
// Every string TrainingCore shows, as a case whose raw value is the English
// text -- the key in Resources/<lang>.lproj/Localizable.strings(dict)
// (TrainingText.swift). Generated together with those four tables from one
// list, so a case, its English and its Czech cannot drift apart;
// TrainingTextTests resolves every case in both languages. Plural keys
// (`.stringsdict`) are the English "other" form.
//
// Add a string: add the case here and the entry to BOTH lproj folders (en
// and cs), with the same format specifiers.
//
// Depended on by: TrainingText and every formatter and builder.

import Foundation

public enum TrainingKey: String, CaseIterable, Sendable {
    /// Sport name.
    case sportRun = "Run"
    /// Sport name (cycling).
    case sportRide = "Ride"
    /// Sport name.
    case sportWalk = "Walk"
    /// Sport name.
    case sportSwim = "Swim"
    /// Sport name, also the strength session type.
    case sportStrength = "Strength"
    /// Sport name, also the mobility session type.
    case sportMobility = "Mobility"
    /// Sport name.
    case sportWinter = "Winter sport"
    /// Sport name for anything else.
    case sportOther = "Other sport"
    /// Session type.
    case typeEasy = "Easy"
    /// Session type (long run).
    case typeLong = "Long"
    /// Session type.
    case typeTempo = "Tempo"
    /// Session type.
    case typeThreshold = "Threshold"
    /// Session type.
    case typeIntervals = "Intervals"
    /// Session type.
    case typeVO2max = "VO2max"
    /// Session type.
    case typeCross = "Cross-training"
    /// Session type for anything else.
    case typeOther = "Other"
    /// Session type, week kind and workout step (easy recovery).
    case recovery = "Recovery"
    /// Session type, week kind and the race badge.
    case race = "Race"
    /// Badge on a test session.
    case badgeTest = "Test"
    /// Session slot: before noon.
    case slotAM = "Morning"
    /// Session slot: after noon.
    case slotPM = "Afternoon"
    /// Session status.
    case statusPlanned = "Planned"
    /// Session status.
    case statusDone = "Done"
    /// Session status.
    case statusMissed = "Missed"
    /// Session status.
    case statusSkipped = "Skipped"
    /// Week row: done, with the option letter (G, A or R).
    case doneWithOption = "Done · %@"
    /// Marks today's date in the plan.
    case today = "Today"
    /// Week status: not yet approved.
    case weekProposed = "Proposed"
    /// Week status.
    case weekApproved = "Approved"
    /// Week status: finished.
    case weekClosed = "Closed"
    /// Week kind in the outline.
    case kindBuild = "Build"
    /// Week kind in the outline: an easier week.
    case kindDeload = "Deload"
    /// Week kind in the outline: before a race.
    case kindTaper = "Taper"
    /// Week kind in the outline.
    case kindTransition = "Transition"
    /// What option G means.
    case optionPlanned = "Planned session"
    /// What option A means.
    case optionEasier = "Easier"
    /// What option R means (no running).
    case optionAlternative = "Alternative"
    /// VoiceOver for an option card: letter, meaning, label.
    case a11yOption = "Option %@, %@: %@"
    /// VoiceOver: this option matches the morning traffic light.
    case a11yMatchesLight = "Matches your morning check"
    /// Session detail: the option that was done, letter and meaning.
    case doneOptionMeaning = "Option %@ · %@"
    /// Session detail: done, but the app can't tell which option.
    case optionNotIdentified = "Option not identified"
    /// Watch push: the option is on the training calendar (not necessarily on the watch yet).
    case watchScheduled = "On Garmin calendar"
    /// Watch push: the option waits to be sent.
    case watchPending = "Not on Garmin calendar yet"
    /// Watch push: the last attempt failed.
    case watchFailed = "Couldn't send to Garmin calendar"
    /// Morning traffic light.
    case lightGreen = "Green"
    /// Morning traffic light.
    case lightAmber = "Amber"
    /// Morning traffic light.
    case lightRed = "Red"
    /// The morning traffic light of a day.
    case lightLine = "Morning check: %@"
    /// A carb-loading day before a race: grams and grams per kilogram.
    case fuelCarbLoad = "Carb load: %@ g carbs (%@ g/kg)"
    /// A carb-loading day, grams only.
    case fuelCarbLoadGrams = "Carb load: %@ g carbs"
    /// A carb-loading day, grams per kilogram only.
    case fuelCarbLoadPerKg = "Carb load: %@ g/kg"
    /// Carbohydrate to take per hour during a session.
    case fuelPerHour = "Fuel: %@ g carbs/h"
    /// Race countdown: the race is today.
    case countdownToday = "today"
    /// Race countdown: the race is tomorrow.
    case countdownTomorrow = "tomorrow"
    /// Race countdown for an approximate date.
    case countdownAboutToday = "about today"
    /// Race countdown for an approximate date.
    case countdownAboutTomorrow = "about tomorrow"
    /// Race countdown. Plural.
    case countdownInDays = "in %lld days"
    /// Race countdown for an approximate date. Plural.
    case countdownInAboutDays = "in about %lld days"
    /// A race on this day; the race's name.
    case raceDayLine = "Race day: %@"
    /// Freshness line: the day the plan describes.
    case noticePlanAsOf = "Plan as of %@"
    /// Freshness line: the plan has no date.
    case noticePlanDateUnknown = "Plan date unknown"
    /// Freshness line: no sync for a day or more. Plural.
    case noticeLastSynced = "Last synced %lld days ago"
    /// The latest plan file could not be read.
    case noticeUnreadable = "Couldn't read the latest plan"
    /// The latest plan file could not be read; the date of the plan still shown.
    case noticeUnreadableShowing = "Couldn't read the latest plan; showing %@"
    /// The plan file is newer than this app version. The app name stays in English.
    case noticeUpdateApp = "Update Jirka's Arc to read this plan"
    /// Quiet hint that a newer app reads more.
    case noticeNewerVersion = "A newer app version reads more of your plan"
    /// Empty state while the first plan downloads.
    case stateFetchingTitle = "Fetching your plan…"
    /// Empty state while the first plan downloads.
    case stateFetchingMessage = "The first time takes a moment."
    /// Empty state: the vault hasn't published a plan.
    case stateNotGeneratedTitle = "No plan data yet"
    /// Empty state: the vault hasn't published a plan.
    case stateNotGeneratedMessage = "Your vault hasn't published it."
    /// Empty state: no training phase.
    case stateNoActivePlanTitle = "No active plan"
    /// Empty state: no training phase.
    case stateNoActivePlanMessage = "Your vault has no training phase right now."
    /// Nothing planned on a day.
    case stateRestDayTitle = "Rest day"
    /// Nothing planned on a day.
    case stateRestDayMessage = "Nothing is planned for this day."
    /// The week exists only in the outline.
    case stateWeekNotWrittenTitle = "Week not written yet"
    /// A week outside every phase.
    case stateNoPlanWeekTitle = "No plan for this week"
    /// A week outside every phase.
    case stateNoPlanWeekMessage = "This week is outside every phase of the season."
    /// Plan week view of an outline-only week.
    case weekNotWrittenMessage = "Sessions for this week aren't written yet"
    /// ISO week number, short (Czech: T for tyden).
    case weekNumber = "W%lld"
    /// ISO week number and its date range.
    case weekLabel = "W%lld · %@"
    /// Week header: kilometres run, no target.
    case weekRun = "Run %@ km"
    /// Week header: kilometres run of the target.
    case weekRunOfTarget = "Run %@ of %@ km"
    /// Week header: the week's running target.
    case weekRunTarget = "Run target %@ km"
    /// Week header: sessions done, missed, of planned.
    case weekSessionsDoneMissed = "%lld done · %lld missed of %lld"
    /// Week header of a week that hasn't started.
    case weekSessionsPlanned = "Sessions planned: %lld"
    /// An activity that matched no planned session.
    case unplanned = "Unplanned"
    /// Workout step.
    case stepWarmUp = "Warm-up"
    /// Workout step.
    case stepCoolDown = "Cool-down"
    /// Workout step: rest between exercises.
    case stepRest = "Rest"
    /// Workout step: an isometric hold.
    case stepHold = "Hold"
    /// Interval step: the recovery after each repeat, a duration.
    case stepRecoveryAfter = "%@ recovery"
    /// The workout has no steps in the plan.
    case stepsNotPublished = "Steps not published"
    /// Exercise side.
    case sideEach = "each side"
    /// Exercise side.
    case sideLeft = "left"
    /// Exercise side.
    case sideRight = "right"
    /// Exercise side.
    case sideBoth = "both sides"
    /// How the done option was recognised.
    case recognisedSport = "Inferred from the sport"
    /// How the done option was recognised: the option letter at the start of the activity's name.
    case recognisedName = "Recognised from the activity's name"
    /// How the session was recognised as done.
    case recognisedTest = "Recorded as a test result"
    /// How the activity was matched to the session.
    case recognisedDateSport = "Matched by date and sport"
    /// Where a session came from: a date.
    case originMovedFrom = "Moved from %@"
    /// Session detail: the session swapped days with another; its old date.
    case originSwappedFrom = "Swapped from %@"
    /// Where a session came from.
    case originRule = "Changed by a rule"
    /// Where a session came from.
    case originChanged = "Changed after planning"
    /// A test before it was done.
    case testNoResult = "No result yet"
    /// The previous result of a test, with its unit.
    case testPrevious = "Previous %@"
    /// Test result against the previous one.
    case testImproved = "Improved"
    /// Test result against the previous one.
    case testWorse = "Worse"
    /// Test result against the previous one.
    case testUnchanged = "Unchanged"
    /// Habit ladder state.
    case habitActive = "Active"
    /// Habit ladder state.
    case habitNext = "Next"
    /// Habit ladder state.
    case habitLater = "Later"
    /// A habit's 14-day adherence has no data.
    case habitNotRecorded = "not recorded yet"
    /// A habit's 14-day adherence: done of expected and percent.
    case habitWindow = "%lld of %lld · %lld %%"
    /// A habit's adherence covers fewer days than the window. Plural.
    case habitRecordedDays = "over %lld recorded days"
    /// A habit done today, of the times expected.
    case habitTodayCount = "Today: %lld of %lld"
    /// The adherence gate for the next habit.
    case habitGate = "Gate: %lld %% · %lld-day window"
    /// The active habit met its gate.
    case habitGateMet = "Gate met: the next habit can start at your Sunday review"
    /// When a habit started: a date.
    case habitStarted = "Started %@"
    /// When a habit can start: a date.
    case habitEarliest = "Earliest start %@"
    /// The plan has no habit ladder.
    case habitsNone = "No habits in this plan"
    /// polish-training-today: the highest active habit's place on the ladder.
    case habitStepOf = "Step %lld of %lld"
    /// polish-training-today: habits done of those expected on the shown day.
    case habitsDoneToday = "%lld of %lld done today"
    /// polish-training-today: an active habit the plan doesn't expect on the shown day.
    case habitNotToday = "Not on today's plan"
    /// polish-training-today: what unlocks the next habit (the current habit's name, the gate percent, the window in days).
    case habitUnlockWhen = "Unlocks when %@ holds %lld %% over a %lld-day window"
    /// polish-training-today: the next habit on the ladder (its name).
    case habitNextStep = "Next step: %@"
    /// Habit schedule.
    case scheduleEveryDay = "Every day"
    /// Habit schedule: times a day.
    case scheduleTimesPerDay = "%lld× a day"
    /// Habit schedule.
    case scheduleOnceAWeek = "Once a week"
    /// Habit schedule: times a week.
    case scheduleTimesPerWeek = "%lld× a week"
    /// Habit schedule. Plural.
    case scheduleEveryNWeeks = "every %lld weeks"
    /// Habit schedule: after these session types.
    case scheduleWithSessions = "After sessions: %@"
    /// add-training-checkins: the check-in row on Today's training card.
    case checkInTitle = "Morning check-in"
    /// VoiceOver for a check-in button: the light and what its option means.
    case a11yCheckInButton = "Morning check-in %@, %@"
    /// A check-in, tick, RPE or note is stored on the phone, not uploaded yet.
    case deliverySaved = "Saved on phone"
    /// A check-in, tick, RPE or note has been uploaded to the vault.
    case deliverySent = "Sent"
    /// The vault has read the event (its projection acknowledged it).
    case deliveryReceived = "Received by the vault"
    /// Reminder title of the morning check-in (every day).
    case reminderCheckInTitle = "How do you feel today?"
    /// Reminder body of the morning check-in outside pain mode: short.
    case reminderCheckInBody = "Green, amber or red?"
    /// Reminder body of the morning check-in in pain mode: the light and the pain score.
    case reminderCheckInBodyPain = "Green, amber or red? Add your pain score too."
    /// Reminder title for the evening habits.
    case reminderHabitsTitle = "Evening habits"
    /// Reminder body for the evening habits.
    case reminderHabitsBody = "Tick today's habits before bed."
    /// improve-food-day-flow: reminder body for the evening habits on a day whose food log is not closed yet.
    case reminderHabitsBodyFoodLog = "Tick today's habits and close your food log."

    /// Season screen: the vault has published no season.
    case seasonNoneTitle = "No season yet"
    /// Season screen: the vault has published no season.
    case seasonNoneMessage = "Your vault hasn't published a season."
    /// Season timeline: a stretch of the season no phase covers.
    case seasonNoPhase = "No phase planned"
    /// How many weeks a phase has. Plural.
    case weeksCount = "%lld weeks"
    /// A race in the past. Plural.
    case countdownDaysAgo = "%lld days ago"
    /// A race with an approximate date in the past. Plural.
    case countdownAboutDaysAgo = "about %lld days ago"
    /// The season's hero race (its main goal).
    case raceHero = "Hero race"
    /// A race no training phase prepares for yet.
    case raceUnanchored = "No phase covers this race yet"
    /// polish-training-today: the season's main race under the next race's countdown (name, countdown).
    case raceMainLine = "Main race: %@ · %@"
    /// Race priority A (a goal race).
    case racePriorityA = "A race"
    /// Race priority B.
    case racePriorityB = "B race"
    /// Race priority C (a training race).
    case racePriorityC = "C race"
    /// Race checkpoint: food and drink.
    case aidFull = "Full aid"
    /// Race checkpoint: water only.
    case aidWater = "Water"
    /// Race checkpoint: nothing to eat or drink.
    case aidNone = "No aid"
    /// Training phase kind.
    case phaseKindBase = "Base"
    /// Training phase kind: race-specific preparation.
    case phaseKindSpecific = "Specific"
    /// Training phase status: not started, still being written.
    case phaseDraft = "Draft"
    /// Phase header: the phase is over.
    case phaseFinished = "Finished"
    /// Phase header: a phase that hasn't started. Plural.
    case phaseStartsIn = "Starts in %lld days"
    /// Phase header: which week of the phase today is.
    case phaseWeekOf = "Week %lld of %lld"
    /// Phase header: days to the phase's end. Plural.
    case phaseDaysLeft = "%lld days left"
    /// Phase weeks: a past week the plan file no longer carries, so its distance isn't known here.
    case weekOutsideWindow = "Not in the app's window"
    /// Phase screen of a phase other than the current one.
    case phaseRestricted = "Goals and rules are published for the current phase only."
    /// Phase recap: kilometres run against the plan, over the weeks with known distance.
    case recapRun = "Ran %@ of %@ km planned"
    /// Phase recap: weeks whose distance was within ten percent of the target.
    case recapWithinTen = "%lld of %lld weeks within 10 %% of target"
    /// Phase recap: the week with the most kilometres and its ISO week number.
    case recapBiggest = "Biggest week: %@ km (W%lld)"
    /// Race: start time.
    case raceStart = "Start %@"
    /// Race or checkpoint: the time limit (duration and clock time).
    case raceCutoff = "Cutoff %@"
    /// A race checkpoint without a name.
    case checkpointNumber = "Checkpoint %lld"
    /// Race checkpoint: the planned arrival (duration and clock time).
    case checkpointTarget = "Target %@"
    /// Race checkpoint: time between the planned arrival and the cutoff.
    case checkpointBuffer = "Buffer %@"
    /// Race checkpoint: the planned arrival is after the cutoff by this much.
    case checkpointOverCutoff = "%@ after the cutoff"
    /// Race fuel: carbohydrate per hour.
    case raceFuelCarbs = "%@ g carbs/h"
    /// Race fuel: how often to eat.
    case raceFuelEvery = "Every %lld min"
    /// Race fuel: fluid per hour.
    case raceFuelFluid = "%@ ml fluid/h"
    /// Race fuel: carbohydrate over the planned finish time.
    case raceFuelTotalCarbs = "About %@ g carbs to the finish"
    /// Race fuel: fluid over the planned finish time, in litres.
    case raceFuelTotalFluid = "About %@ l fluid to the finish"
    /// Carb load on the race day itself.
    case raceDay = "Race day"
    /// Carb load: days before the race. Plural.
    case carbLoadDaysBefore = "%lld days before"
    /// Carb load: days after the race. Plural.
    case carbLoadDaysAfter = "%lld days after"
    /// Carb load day: grams of carbohydrate and grams per kilogram.
    case carbLoadAmount = "%@ g carbs · %@ g/kg"
    /// Carb load day: grams of carbohydrate.
    case carbLoadGrams = "%@ g carbs"
    /// Carb load day: grams of carbohydrate per kilogram of body weight.
    case carbLoadPerKg = "%@ g/kg"
    /// Carb load day without an amount.
    case carbLoadUnknown = "Amount not set"
    /// Carb load: the grams come from the plan file.
    case carbLoadFromPlan = "From your plan"
    /// Carb load: grams worked out from the body weight in the plan.
    case carbLoadEstimate = "Estimated for %@ kg"
    /// Carb load: grams can't be worked out without a body weight.
    case carbLoadNoWeight = "No body weight in the plan to count grams"
    /// Race gear that is required.
    case gearMandatory = "Mandatory"
    /// Race gear that is not required.
    case gearOptional = "Optional"
    /// Race screen: the race has no preparation yet.
    case raceStub = "Race prep not written yet"
    /// Race screen: the vault has a report for the race.
    case raceReported = "Race report written"
    /// Statistics scope: the whole season.
    case statsWholeSeason = "Whole season"
    /// Statistics: share of the sessions due so far that were done (a percentage).
    case statsAdherence = "Done %@ of the sessions due so far"
    /// Statistics: nothing has been due in the scope yet.
    case statsNoneDue = "No sessions due yet"
    /// Statistics: started weeks the plan file no longer carries (a list of week numbers); not counted.
    case statsOutsideWindow = "Not in the app's window: %@"
    /// Statistics: sessions done, missed and still planned.
    case statsCounts = "%lld done · %lld missed · %lld planned"
    /// Statistics: sessions skipped.
    case statsSkipped = "%lld skipped"
    /// Statistics: a number of sessions. Plural.
    case statsSessions = "%lld sessions"
    /// Statistics: no done session with G/A/R options in the scope.
    case statsNoOptions = "No traffic-light session done yet"
    /// Statistics: kilometres run of the week's target.
    case statsOfTarget = "%@ of %@ km"
    /// Statistics: the run target summed over the weeks.
    case statsPlannedTotal = "Planned %@ km in total"
    /// Statistics: mean kilometres per week with a known distance.
    case statsMeanWeekly = "Average %@ km a week"
    /// Statistics: a test never done.
    case statsNoResults = "No results yet"
    /// Statistics: a test's left and right values (L = left, R = right).
    case statsLeftRight = "L %@ · R %@"
    /// Statistics: the difference between left and right as a percentage.
    case statsAsymmetry = "Asymmetry %@"
    // add-plan-editing: plan changes from the phone.
    /// Plan change: move the session to another day (the day).
    case editMoveTo = "Move to %@"
    /// Plan change: swap days with another session (its title, its day).
    case editSwapWith = "Swap with %@ (%@)"
    /// Plan change: skip the session.
    case editSkip = "Skip"
    /// Plan change: skip the session, with the owner's reason.
    case editSkipReason = "Skip: %@"
    /// Plan change: undo a skip.
    case editUnskip = "Undo the skip"
    /// Plan change: override a training rule's edit of the session (the rule's id).
    case editOverride = "Override the rule %@"
    /// Plan change status: waiting for the vault, only saved on the phone.
    case editPendingSaved = "Pending · Saved on phone"
    /// Plan change status: waiting for the vault, uploaded.
    case editPendingSent = "Pending · Sent"
    /// Plan change status: its withdrawal waits for the vault, only saved on the phone.
    case editWithdrawingSaved = "Withdrawal pending · Saved on phone"
    /// Plan change status: its withdrawal waits for the vault, uploaded.
    case editWithdrawingSent = "Withdrawal pending · Sent"
    /// Plan change status: the vault applied it.
    case editApplied = "Applied"
    /// Plan change status: the vault did not apply it (the session was elsewhere or gone).
    case editNotApplied = "Not applied"
    /// Plan change status: the vault refused it.
    case editRefused = "Refused"
    /// Plan change status: withdrawn in the app.
    case editWithdrawn = "Withdrawn"
    /// Plan change status: the vault answered with a status this app doesn't know.
    case editAnswered = "Answered by the vault"
    /// Badge on a session: a plan change waits for the vault.
    case editBadgePending = "Change pending"
    /// Badge on a session: the vault did not apply the phone's plan change.
    case editBadgeNotApplied = "Change not applied"
    /// Session detail: why a race session can't be changed.
    case editBlockRace = "A race: the organiser sets its date, so it can't be moved, swapped or skipped here."
    /// Session detail: why a past session can't be moved or swapped.
    case editBlockPastDay = "Past days follow the activities: they can only be skipped or unskipped."
    /// Session detail: why a done session can't be moved, swapped or skipped.
    case editBlockDone = "Done: this session follows its activity."
    /// Session detail: the week has no revision, so the phone can't change it.
    case editBlockNoRevision = "This week can't be changed from the phone."
    /// Session detail: a plan change on the session still waits for the vault.
    case editBlockWaiting = "Waiting for the vault's answer. Withdraw the change to make another."
    /// Warning before overriding a training rule (the rule's id).
    case editOverrideTitle = "Override the rule %@?"
    /// Warning before overriding a training rule: why the rule exists and that the override is logged.
    case editOverrideMessage = "The rule changed this session as a precaution. You have the last word, and the override is logged for the Sunday review."
    // add-checkin-pain-score: the morning pain step and pain tags.
    /// Pain site: the left Achilles tendon.
    case painSiteAchillesLeft = "Achilles (left)"
    /// Pain site: the right Achilles tendon.
    case painSiteAchillesRight = "Achilles (right)"
    /// Pain site: the left knee.
    case painSiteKneeLeft = "Knee (left)"
    /// Pain site: the right knee.
    case painSiteKneeRight = "Knee (right)"
    /// Pain site: anywhere else (with a short note).
    case painSiteOther = "Other site"
    /// A pain score out of ten (the score, e.g. 4.5).
    case painScore = "%@/10"
    /// A pain tag: the site and its score out of ten (e.g. Achilles (left) 4.5/10).
    case painTag = "%@ %@/10"
    /// A pain tag for another site: the site, its score out of ten and the owner's note.
    case painTagNote = "%@ %@/10 (%@)"
    /// The day's recorded morning pain (the sites with their scores).
    case painLine = "Pain: %@"
    /// The day's morning check recorded that nothing hurts.
    case painNone = "Pain: none"
    /// Title of the pain step under the morning check-in.
    case painTitle = "Pain this morning"
    /// The pain scale, under the pain step's title.
    case painHint = "0 = no pain, 10 = worst imaginable"
    /// Button: record the morning pain with the check-in.
    case painSave = "Save pain"
    /// Button: fold the pain step without recording anything.
    case painNotNow = "Not now"
    /// Button: change the morning pain recorded today.
    case painEdit = "Edit pain"
    /// Small link under the morning check-in outside pain mode: opens the pain step.
    case painSomethingHurts = "Something hurts?"
    /// Menu: add another painful site to the morning pain.
    case painAddSite = "Add another site"
    /// VoiceOver for the button that removes a site from the morning pain (the site).
    case painRemoveSite = "Remove %@"
    /// Placeholder of the note for another painful site.
    case painNotePlaceholder = "What hurts? (short note)"
    /// The pain step with every site removed: saving records that nothing hurts.
    case painNothingHurts = "Nothing hurts"
    /// VoiceOver value of a pain score control (the score).
    case a11yPainValue = "%@ of 10"
    /// add-interactive-habits: a habit's streak counted in times the plan expected it.
    case habitStreakTimes = "%lld× in a row"
    /// add-interactive-habits: a habit with no current streak.
    case habitStreakNone = "No streak yet"
    /// add-interactive-habits: a habit's best streak (a count).
    case habitStreakBest = "Best: %lld"
    /// add-interactive-habits: caption under a habit's current streak figure.
    case habitStreakCurrentCaption = "Current streak"
    /// add-interactive-habits: caption under a habit's best streak figure.
    case habitStreakBestCaption = "Best streak"
    /// add-interactive-habits: when a habit was last done (a date).
    case habitStreakLastDone = "Last done %@"
    /// add-interactive-habits: the phone's streak count stopped where its known days end.
    case habitStreakMayBeLonger = "The streak may be longer: the phone doesn't know the days before."
    /// add-interactive-habits: title of a habit's adherence over 7, 14, 30 and 84 days.
    case habitAdherenceTitle = "Adherence"
    /// add-interactive-habits: an adherence window in days, abbreviated (7 d).
    case habitWindowDays = "%lld d"
    /// add-interactive-habits: a percent.
    case habitPct = "%lld %%"
    /// add-interactive-habits: why a long adherence window has no percent yet.
    case habitAdherencePartial = "Longer windows fill in once the vault publishes the habit's history."
    /// add-interactive-habits: a habit expected today and not done yet.
    case habitNotDoneYet = "Not done yet"
    /// add-interactive-habits: doses of a habit done of those expected that day.
    case habitDoseCount = "%lld of %lld"
    /// add-interactive-habits: a day the plan doesn't expect the habit.
    case habitNotPlanned = "Not planned"
    /// add-interactive-habits: a day with nothing known about the habit.
    case habitNoRecord = "No record"
    /// add-interactive-habits: calendar legend: some doses of the day done.
    case habitPartly = "Partly"
    /// add-interactive-habits: button: the habit was done that day.
    case habitMarkDone = "Mark done"
    /// add-interactive-habits: button: the habit was not done that day.
    case habitMarkNotDone = "Mark not done"
    /// add-interactive-habits: VoiceOver for the button adding a dose of a multi-dose habit.
    case habitDoseAdd = "One more"
    /// add-interactive-habits: VoiceOver for the button removing a dose of a multi-dose habit.
    case habitDoseRemove = "One fewer"
    /// add-interactive-habits: a past day too old to fill in (the window in days).
    case habitLockedWindow = "Outside the back-fill window (%lld d)"
    /// add-interactive-habits: a day the plan doesn't expect the habit can't be ticked.
    case habitLockedNotPlanned = "Not on the plan that day"
    /// add-interactive-habits: a day without plan data can't be ticked.
    case habitLockedUnknown = "The phone doesn't know that day's plan"
    /// add-interactive-habits: habits can't be ticked without a working vault connection.
    case habitLockedReadOnly = "Turn on and test the vault connection to log habits"
    /// add-interactive-habits: hint under a habit's calendar (the back-fill window in days).
    case habitBackfillHint = "Tap a day to fill it in. Back-fill window: %lld d."
    /// add-interactive-habits: title of a habit's history calendar.
    case habitHistoryTitle = "Last 12 weeks"
    /// add-interactive-habits: title of a habit's recent log entries.
    case habitLogTitle = "Recent entries"
    /// add-interactive-habits: a habit with no log entries.
    case habitLogEmpty = "Nothing logged yet"
    /// add-interactive-habits: a ladder step that is active and already followed by a later active step.
    case habitStepEstablished = "Established"
    /// add-interactive-habits: the highest active ladder step.
    case habitStepCurrent = "Current step"
    /// add-interactive-habits: a ladder step that has not started.
    case habitStepLocked = "Locked"
    /// add-interactive-habits: a later ladder step unlocks after the step before it (that habit's name).
    case habitUnlockAfter = "Unlocks after: %@"
    /// add-interactive-habits: a ladder step's number.
    case habitStepNumber = "Step %lld"
    /// add-interactive-habits: every habit expected on the shown day is done.
    case habitAllDoneToday = "All of today's habits done"
    /// add-interactive-habits: VoiceOver for a calendar day (the date, its state).
    case habitDayA11y = "%@: %@"
    /// add-interactive-habits: a habit the vault measures from activities or the plan can't be ticked by hand.
    case habitLockedMeasured = "Measured from your activities and the plan"
    /// add-interactive-habits: a day after today can't be ticked (the vault refuses it).
    case habitLockedFuture = "This day hasn't started yet"
    /// add-interactive-habits: title of the list of ticks the vault refused.
    case habitRefusedTitle = "Not accepted by the vault"
    /// add-interactive-habits: a tick the vault refused without giving a reason.
    case habitRefusedFallback = "The vault did not accept this entry."
    /// add-interactive-habits: a habit's streak in days. Plural.
    case habitStreakDays = "%lld days in a row"
    /// add-interactive-habits: a habit's streak in weeks. Plural.
    case habitStreakWeeks = "%lld weeks in a row"
    /// add-interactive-habits: the streak and percents are the phone's own count over the days it knows. Plural.
    case habitEstimateNote = "Counted on the phone from the last %lld days it knows"
    /// add-training-gates-and-load: a value the vault does not know (a data gap, never 0).
    case unknownValue = "–"
    /// add-training-gates-and-load: placeholder of an optional note field.
    case noteOptional = "Note (optional)"
    /// add-training-gates-and-load: button closing a sheet without recording.
    case actionCancel = "Cancel"
    /// add-training-gates-and-load: button taking back what was just recorded by hand.
    case actionUndo = "Undo"
    /// add-training-gates-and-load: under something recorded on the phone that the vault has not read yet.
    case answersAfterSync = "The plan answers after the next sync."
    /// add-training-gates-and-load: title of the weekly gate test card.
    case gateTitle = "Weekly gate test"
    /// add-training-gates-and-load: what the two gate test sliders ask.
    case gateHint = "Pain 0–10 when walking, and on 20 single-leg hops."
    /// add-training-gates-and-load: gate test slider: pain when walking.
    case gateWalkLabel = "Walking"
    /// add-training-gates-and-load: gate test slider: pain on 20 single-leg hops.
    case gateHopLabel = "20 single-leg hops"
    /// add-training-gates-and-load: gate test: which body site was tested.
    case gateSiteLabel = "Tested site"
    /// add-training-gates-and-load: button recording the gate test.
    case gateSave = "Save test"
    /// add-training-gates-and-load: button opening the gate test editor when the week has no test.
    case gateRecord = "Record a test"
    /// add-training-gates-and-load: button opening the gate test editor when the week already has a test.
    case gateRecordAgain = "Test again"
    /// add-training-gates-and-load: gate card without any test.
    case gateNone = "No gate test yet"
    /// add-training-gates-and-load: gate card: the date of the last test.
    case gateTested = "Tested %@"
    /// add-training-gates-and-load: gate verdict from the vault: the walking score, running allowed.
    case gateWalkAllowed = "Walking %@ — running is allowed"
    /// add-training-gates-and-load: gate verdict from the vault: the walking score, running not allowed.
    case gateWalkLocked = "Walking %@ — no running for now"
    /// add-training-gates-and-load: gate card: the walking score when the vault gave no verdict.
    case gateWalkPlain = "Walking %@"
    /// add-training-gates-and-load: gate verdict from the vault: the hop score, speed work allowed.
    case gateHopAllowed = "Hops %@ — speed, hills and jumps are allowed"
    /// add-training-gates-and-load: gate verdict from the vault: the hop score, speed work not allowed.
    case gateHopLocked = "Hops %@ — speed, hills and jumps stay locked"
    /// add-training-gates-and-load: gate card: the hop score when the vault gave no verdict.
    case gateHopPlain = "Hops %@"
    /// add-training-gates-and-load: gate card: neutral advice after several weekly tests above 2/10. Plural.
    case gatePhysio = "Hops above 2/10 for %lld weeks in a row — a physio check is advised."
    /// add-training-gates-and-load: gate card: the vault calls the test stale.
    case gateStale = "This test is more than two weeks old."
    /// add-training-gates-and-load: gate card: the phone's own test the vault has not judged yet (date, two scores).
    case gatePending = "Your test of %@: walking %@ · hops %@"
    /// add-training-gates-and-load: session detail: title of the pain block beside the RPE.
    case sessionPainTitle = "Pain during and after"
    /// add-training-gates-and-load: session pain slider: pain during the session.
    case sessionPainDuring = "During"
    /// add-training-gates-and-load: session pain slider: pain after the session.
    case sessionPainAfter = "After"
    /// add-training-gates-and-load: button recording the session pain with the RPE.
    case sessionPainSave = "Save session pain"
    /// add-training-gates-and-load: session pain: Save needs an RPE.
    case sessionPainNeedsRPE = "Choose the effort first — the pain is sent with it."
    /// add-training-gates-and-load: session detail: pain was asked and nothing hurt.
    case sessionPainNone = "Pain: nothing hurt"
    /// add-training-gates-and-load: session detail: one site's recorded pain (site, two scores).
    case sessionPainLine = "%@: during %@ · after %@"
    /// add-training-gates-and-load: morning pain step: how a site settled overnight (site, two scores).
    case painSettledLine = "%@ — yesterday after the session: %@ → today: %@"
    /// add-training-gates-and-load: week load line: run km of the week's target.
    case loadWeekOfTarget = "Week %@ of %@ km"
    /// add-training-gates-and-load: week load line: run km, no target.
    case loadWeek = "Week %@ km"
    /// add-training-gates-and-load: week load line: km over the week's target (a warning, never praise).
    case loadOverPlan = "%@ km over plan"
    /// add-training-gates-and-load: week load line: run km no session planned.
    case loadUnplanned = "%@ km unplanned"
    /// add-training-gates-and-load: week load line: the longest run against the vault's cap.
    case loadLongestOfCap = "longest %@ of %@ km cap"
    /// add-training-gates-and-load: week load line: climb of the week's runs in metres.
    case loadHills = "hills %@ m"
    /// add-training-gates-and-load: week load line: how many done sessions the vault classes as hard.
    case loadHardSessions = "hard sessions %@"
    /// add-training-gates-and-load: amber badge on an unplanned run of a week at or over its target.
    case overPlanBadge = "Over plan"
    /// add-training-gates-and-load: session detail: button for a session done without a recorded activity.
    case manualDoneAction = "Mark done (no watch)"
    /// add-training-gates-and-load: title of the sheet and card for a session done by hand.
    case manualDoneTitle = "Done without a watch"
    /// add-training-gates-and-load: session status: done, said by hand, no activity.
    case doneByHand = "Done (logged by hand)"
    /// add-training-gates-and-load: session detail: an activity matched and a manual record exists too.
    case manualAlsoLogged = "Also logged by hand: %@"
    /// add-training-gates-and-load: done-by-hand sheet: which option was done.
    case manualOptionLabel = "Option done"
    /// add-training-gates-and-load: done-by-hand sheet: how long it took.
    case manualMinutesLabel = "Minutes"
    /// add-training-gates-and-load: a distance field in kilometres.
    case distanceKmLabel = "Distance (km)"
    /// add-training-gates-and-load: button recording a session as done by hand.
    case manualSave = "Save as done"
    /// add-training-gates-and-load: race screen: title of the result card.
    case raceResultTitle = "Result"
    /// add-training-gates-and-load: race screen: button opening the result sheet.
    case raceResultAction = "How did it go?"
    /// add-training-gates-and-load: race screen: button opening the result sheet when a result exists.
    case raceResultEdit = "Change the result"
    /// add-training-gates-and-load: race result status (neutral wording).
    case raceStatusDNF = "Did not finish"
    /// add-training-gates-and-load: race result status (neutral wording).
    case raceStatusDNS = "Did not start"
    /// add-training-gates-and-load: race result reason: the pre-agreed stop rule ended the race.
    case raceReasonStopRule = "Stopped by the stop rule"
    /// add-training-gates-and-load: race result reason.
    case raceReasonInjury = "Injury"
    /// add-training-gates-and-load: race result reason.
    case raceReasonIllness = "Illness"
    /// add-training-gates-and-load: race result reason.
    case raceReasonOther = "Other reason"
    /// add-training-gates-and-load: race result sheet: leave the reason out.
    case raceReasonNone = "No reason given"
    /// add-training-gates-and-load: race result: the elapsed time shown under the organiser's results time.
    case raceElapsed = "%@ elapsed"
    /// add-training-gates-and-load: race result: laps completed. Plural.
    case raceLaps = "%lld laps"
    /// add-training-gates-and-load: race result: the vault says the typed goal was reached.
    case raceGoalReached = "Goal reached"
    /// add-training-gates-and-load: race result: the race report says it is a personal record.
    case racePR = "Personal record"
    /// add-training-gates-and-load: race result: where the record came from.
    case raceResultFromReport = "From the race report"
    /// add-training-gates-and-load: race result: where the record came from.
    case raceResultFromApp = "Logged in the app"
    /// add-training-gates-and-load: race result the vault refused without giving a reason.
    case raceResultRefused = "The vault did not accept this result."
    /// add-training-gates-and-load: race result sheet: the status picker.
    case raceResultStatusLabel = "How it ended"
    /// add-training-gates-and-load: race result sheet: the reason picker.
    case raceResultReasonLabel = "Reason"
    /// add-training-gates-and-load: race result sheet: the elapsed time field.
    case raceResultTimeLabel = "Elapsed time (h:mm:ss)"
    /// add-training-gates-and-load: race result sheet: the optional organiser's time field.
    case raceResultOfficialLabel = "Time in the results, if different (h:mm:ss)"
    /// add-training-gates-and-load: race result sheet: laps completed (lap races).
    case raceResultLapsLabel = "Laps"
    /// add-training-gates-and-load: button recording the race result.
    case raceResultSave = "Save result"
    /// add-training-gates-and-load: race result sheet: why only one status is offered before the race.
    case raceResultBeforeRace = "Before race day only a non-start can be recorded."
    /// add-training-gates-and-load: race result sheet: the time format.
    case raceTimeHint = "Write a time as h:mm:ss, for example 3:24:10."
    /// add-training-gates-and-load: button retracting the phone's own race result.
    case raceResultWithdraw = "Withdraw this result"
    /// add-training-gates-and-load: session detail: title of the fuel log card.
    case fuelLogTitle = "Fuel log"
    /// add-training-gates-and-load: button opening the fuel log sheet.
    case fuelLogAction = "Log fuel"
    /// add-training-gates-and-load: button opening the fuel log sheet when a log exists.
    case fuelLogEdit = "Change the fuel log"
    /// add-training-gates-and-load: fuel log sheet: grams of carbohydrate eaten.
    case fuelCarbsLabel = "Carbs (g)"
    /// add-training-gates-and-load: fuel log sheet: millilitres drunk.
    case fuelFluidLabel = "Fluid (ml)"
    /// add-training-gates-and-load: fuel log sheet: how long the session took.
    case fuelDurationLabel = "Duration (min), if you know it"
    /// add-training-gates-and-load: button recording the fuel log.
    case fuelSave = "Save fuel log"
    /// add-training-gates-and-load: fuel log: grams eaten.
    case fuelLogCarbs = "%@ g carbs eaten"
    /// add-training-gates-and-load: fuel log: millilitres drunk.
    case fuelLogFluid = "%@ ml fluid"
    /// add-training-gates-and-load: fuel log: the vault's grams per hour against the plan.
    case fuelLogPerHourOfPlan = "%@ g/h of %@ g/h planned"
    /// add-training-gates-and-load: fuel log: the vault's grams per hour, no plan figure.
    case fuelLogPerHour = "%@ g/h"
    /// add-training-gates-and-load: fuel log without a known duration.
    case fuelNoDuration = "Add the duration to see grams per hour."
    /// add-training-gates-and-load: fuel log chip (neutral): below the planned grams per hour.
    case fuelBelow = "Below plan"
    /// add-training-gates-and-load: fuel log chip (neutral): within the planned grams per hour.
    case fuelOn = "On plan"
    /// add-training-gates-and-load: fuel log chip (neutral): above the planned grams per hour.
    case fuelAbove = "Above plan"
    /// add-training-gates-and-load: Today chip: the day of the recovery window and its length (14 or 7).
    case recoveryChip = "Recovery day %lld of %lld"
    /// add-training-gates-and-load: Today chip: the last day of the recovery window.
    case recoveryUntil = "until %@"
    /// add-training-gates-and-load: Today chip: the race the recovery window follows.
    case recoveryAfterRace = "After %@"
    /// add-training-gates-and-load: recovery window: what the first week after a marathon means.
    case recoveryNoRunning = "No running this week — walking, mobility and sleep."
    /// add-training-gates-and-load: recovery window: what the second week after a marathon means.
    case recoveryEasyOnly = "Easy running only — no hard sessions yet."
    /// add-training-gates-and-load: recovery window: what two weeks after a very long race mean.
    case recoveryNoBuild = "Easy only — no build for two weeks."
    /// add-training-gates-and-load: recovery window: the seven-day window after a race that was not finished.
    case recoveryShortWeek = "A week of recovery after a race that ended early."
    /// Keys that live in `.stringsdict` (plural forms).
    public var isPlural: Bool {
        switch self {
        case .countdownInDays, .countdownInAboutDays, .noticeLastSynced, .habitRecordedDays, .scheduleEveryNWeeks, .weeksCount, .countdownDaysAgo, .countdownAboutDaysAgo, .phaseStartsIn, .phaseDaysLeft, .carbLoadDaysBefore, .carbLoadDaysAfter, .statsSessions: return true
        // add-interactive-habits (its own line, so the list above stays as it was).
        case .habitStreakDays, .habitStreakWeeks, .habitEstimateNote: return true
        // add-training-gates-and-load (its own line, like the one above).
        case .gatePhysio, .raceLaps: return true
        default: return false
        }
    }
}
