ALTER TABLE trust.phone_challenges
    ALTER COLUMN challenge_id SET DEFAULT gen_random_uuid();
