-- Renaming "Quick Win" -> "اقدامات زودبازده" in the app's UI (index.html)
-- included the "Quick Win منتخب" option in QW_DECISION_OPTIONS, whose value
-- is stored verbatim in cases.decision (the <option value> equals its label
-- there). Update any rows already carrying the old string so they keep
-- matching the frontend's isNewlySelected / DECIDED_STATUSES checks.

update cases
    set decision = 'اقدام زودبازده منتخب'
    where decision = 'Quick Win منتخب';
