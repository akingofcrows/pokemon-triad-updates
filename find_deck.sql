SELECT d.id as deck_id, d.name, d.card_ids FROM triad_decks d WHERE d.user_id=1 AND d.name LIKE '%Rocket%' OR d.name LIKE '%Dark%';
