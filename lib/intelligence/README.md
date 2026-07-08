# Lexi on-device bridge — spec §14. No stable Flutter package; written as a per-platform
# method channel (Swift <-> Apple Foundation Models, Kotlin <-> Gemini Nano).
# Implements lib/executive/planner.dart's PlanAdvisor via LexiPlanAdvisor
# (lib/intelligence/lexi_plan_advisor.dart).
#
# Status:
#   Android (Gemini Nano / AICore) — Dart + Kotlin implemented (LexiPlanAdvisor,
#     LexiBridge.kt). NOT yet buildable: android/app/build.gradle doesn't exist
#     in this repo yet (`flutter create` generates it) — see
#     GRADLE_AICORE_SETUP.md for the exact dependency to add once it does.
#     Even once buildable, AICore only runs on Android 14 QPR1+ / Pixel 9+
#     hardware with the model already downloaded; every other device/config
#     sees LexiPlanAdvisor NoOp silently (by design, not a bug).
#   iOS (Apple Foundation Models) — not started.
