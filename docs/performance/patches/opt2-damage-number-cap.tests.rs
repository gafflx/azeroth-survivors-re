// --- the damage-number budget ---

#[test]
fn damage_numbers_stop_at_the_cap_but_crits_still_show() {
    use super::units::{NumberBudget, MAX_DAMAGE_NUMBERS};
    let mut budget = NumberBudget::default();
    // A burst in one instant fills the cap; the next plain hit is not shown, a crit is.
    for _ in 0..MAX_DAMAGE_NUMBERS {
        assert!(budget.admit(10.0, false));
    }
    assert!(!budget.admit(10.0, false));
    assert!(budget.admit(10.0, true));
    // Still within the numbers' 1.5 s: still full.
    assert!(!budget.admit(11.4, false));
    // Once they have floated away, plain hits show again.
    assert!(budget.admit(11.5, false));
}

#[test]
fn a_steady_stream_of_damage_numbers_holds_at_the_cap() {
    use super::units::{NumberBudget, MAX_DAMAGE_NUMBERS};
    let mut budget = NumberBudget::default();
    // 200 plain hits a second for 10 s: about 64 per 1.5 s get through, never more.
    let mut shown_at: Vec<f64> = Vec::new();
    for i in 0..2000 {
        let now = f64::from(i) / 200.0;
        if budget.admit(now, false) {
            shown_at.push(now);
        }
    }
    for (i, &t) in shown_at.iter().enumerate() {
        let alive = shown_at[..=i].iter().filter(|&&s| t - s < 1.5).count();
        assert!(alive <= MAX_DAMAGE_NUMBERS, "{alive} numbers alive at {t}");
    }
    let expected = (10.0 / 1.5 * MAX_DAMAGE_NUMBERS as f64) as usize;
    assert!(shown_at.len().abs_diff(expected) <= MAX_DAMAGE_NUMBERS);
}

