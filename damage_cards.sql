-- Find Houndour, Murkrow, and Rocket Dark deck cards
SELECT id, card_id, level, condition_value FROM triad_cards WHERE user_id=1 AND card_id IN ('card_houndour_1', 'card_murkrow_1');

-- Find cards that might be in Rocket Dark deck (dark-type Pokemon)
SELECT id, card_id, level, condition_value FROM triad_cards WHERE user_id=1 AND card_id LIKE 'card_%' ORDER BY card_id;
