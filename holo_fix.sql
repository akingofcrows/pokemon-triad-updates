ALTER TABLE triad_cards ADD COLUMN IF NOT EXISTS is_reverse_holo TINYINT DEFAULT 0;
SELECT id, card_id, level, is_shiny FROM triad_cards WHERE user_id=1 AND card_id='trainer_lorelei';
