CREATE TABLE `ranking_sources` (
	`source` text NOT NULL,
	`mode` text NOT NULL,
	`name` text NOT NULL,
	`games` integer DEFAULT 0 NOT NULL,
	`wins` integer DEFAULT 0 NOT NULL,
	`best_score` integer DEFAULT 0 NOT NULL,
	`made` integer DEFAULT 0 NOT NULL,
	`attempts` integer DEFAULT 0 NOT NULL,
	`updated_at` integer NOT NULL,
	PRIMARY KEY(`source`, `mode`, `name`)
);
--> statement-breakpoint
CREATE INDEX `ranking_mode_name` ON `ranking_sources` (`mode`,`name`);