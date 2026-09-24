import {sqliteTable,text,integer,primaryKey,index} from 'drizzle-orm/sqlite-core';
export const rankingSources=sqliteTable('ranking_sources',{
 source:text('source').notNull(),mode:text('mode').notNull(),name:text('name').notNull(),
 games:integer('games').notNull().default(0),wins:integer('wins').notNull().default(0),
 bestTimeMs:integer('best_time_ms'),
 bestScore:integer('best_score').notNull().default(0),made:integer('made').notNull().default(0),attempts:integer('attempts').notNull().default(0),
 updatedAt:integer('updated_at').notNull()
},t=>[primaryKey({columns:[t.source,t.mode,t.name]}),index('ranking_mode_name').on(t.mode,t.name)]);
