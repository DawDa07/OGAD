import unittest
from datetime import datetime

import league_limit as ll


def ts(s):
    return datetime.strptime(s, "%Y-%m-%d %H:%M").timestamp()


def fresh():
    return {"games": {}, "current_game_start": None, "last_game_end": None}


# 2026-10-14 is a Wednesday, 2026-10-17 a Saturday.
class TickTest(unittest.TestCase):
    def play(self, state, start, end):
        ll.tick(state, ts(start), game_running=True, client_running=True)
        return ll.tick(state, ts(end), game_running=False, client_running=True)

    def test_first_game_is_allowed_and_counted(self):
        state = fresh()
        actions, _ = ll.tick(state, ts("2026-10-14 18:00"), True, True)
        self.assertEqual(actions, [])
        self.play(state, "2026-10-14 18:00", "2026-10-14 18:30")
        self.assertEqual(state["games"], {"2026-10-14": 1})

    def test_client_allowed_during_grace_then_closed(self):
        state = fresh()
        actions, _ = self.play(state, "2026-10-14 18:00", "2026-10-14 18:30")
        self.assertEqual(actions, [])
        actions, _ = ll.tick(state, ts("2026-10-14 18:33"), False, True)
        self.assertEqual([a for a, _ in actions], ["kill_client"])

    def test_second_game_is_killed(self):
        state = fresh()
        self.play(state, "2026-10-14 18:00", "2026-10-14 18:30")
        actions, _ = ll.tick(state, ts("2026-10-14 18:31"), True, True)
        self.assertEqual([a for a, _ in actions], ["kill_game"])
        self.assertIsNone(state["current_game_start"])

    def test_weekend_limit(self):
        state = fresh()
        for i in range(ll.WEEKEND_GAMES_PER_DAY):
            actions, _ = ll.tick(state, ts(f"2026-10-17 1{i}:00"), True, True)
            self.assertEqual(actions, [])
            ll.tick(state, ts(f"2026-10-17 1{i}:30"), False, True)
        self.assertEqual(state["games"], {"2026-10-17": ll.WEEKEND_GAMES_PER_DAY})
        actions, _ = ll.tick(state, ts("2026-10-17 23:00"), True, True)
        self.assertEqual([a for a, _ in actions], ["kill_game"])

    def test_friday_night_is_a_weekday(self):
        state = fresh()
        self.play(state, "2026-10-17 01:00", "2026-10-17 01:30")
        actions, _ = ll.tick(state, ts("2026-10-17 01:31"), True, True)
        self.assertEqual([a for a, _ in actions], ["kill_game"])

    def test_remake_does_not_count(self):
        state = fresh()
        self.play(state, "2026-10-14 18:00", "2026-10-14 18:03")
        self.assertEqual(state["games"], {})

    def test_late_night_counts_toward_previous_day(self):
        state = fresh()
        self.play(state, "2026-10-15 01:00", "2026-10-15 01:30")
        self.assertEqual(state["games"], {"2026-10-14": 1})

    def test_resets_next_day(self):
        state = fresh()
        self.play(state, "2026-10-14 18:00", "2026-10-14 18:30")
        actions, _ = ll.tick(state, ts("2026-10-15 10:00"), False, True)
        self.assertEqual(actions, [])
        actions, _ = ll.tick(state, ts("2026-10-15 10:05"), True, True)
        self.assertEqual(actions, [])


if __name__ == "__main__":
    unittest.main()
