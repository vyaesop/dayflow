CREATE TYPE "public"."column_scope" AS ENUM('items', 'subitems');--> statement-breakpoint
ALTER TYPE "public"."activity_event" ADD VALUE 'item_trashed';--> statement-breakpoint
ALTER TYPE "public"."activity_event" ADD VALUE 'item_restored';--> statement-breakpoint
ALTER TYPE "public"."activity_event" ADD VALUE 'item_moved_to_board';--> statement-breakpoint
ALTER TYPE "public"."activity_event" ADD VALUE 'board_archived';--> statement-breakpoint
ALTER TYPE "public"."activity_event" ADD VALUE 'board_trashed';--> statement-breakpoint
ALTER TYPE "public"."activity_event" ADD VALUE 'board_restored';--> statement-breakpoint
ALTER TYPE "public"."activity_event" ADD VALUE 'column_moved';--> statement-breakpoint
ALTER TYPE "public"."activity_event" ADD VALUE 'activity_undone';--> statement-breakpoint
ALTER TYPE "public"."column_type" ADD VALUE 'long_text';--> statement-breakpoint
ALTER TYPE "public"."column_type" ADD VALUE 'email';--> statement-breakpoint
ALTER TYPE "public"."column_type" ADD VALUE 'phone';--> statement-breakpoint
ALTER TYPE "public"."column_type" ADD VALUE 'files';--> statement-breakpoint
ALTER TYPE "public"."column_type" ADD VALUE 'rating';--> statement-breakpoint
ALTER TYPE "public"."column_type" ADD VALUE 'item_id';--> statement-breakpoint
ALTER TYPE "public"."column_type" ADD VALUE 'creation_log';--> statement-breakpoint
ALTER TYPE "public"."column_type" ADD VALUE 'last_updated';--> statement-breakpoint
ALTER TYPE "public"."column_type" ADD VALUE 'auto_number';--> statement-breakpoint
CREATE TABLE "update_reactions" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"update_id" uuid NOT NULL,
	"user_id" uuid NOT NULL,
	"emoji" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
DROP INDEX "activity_log_board_idx";--> statement-breakpoint
ALTER TABLE "board_views" ADD COLUMN "updated_at" timestamp with time zone DEFAULT now() NOT NULL;--> statement-breakpoint
ALTER TABLE "boards" ADD COLUMN "trashed_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "columns" ADD COLUMN "scope" "column_scope" DEFAULT 'items' NOT NULL;--> statement-breakpoint
ALTER TABLE "items" ADD COLUMN "parent_item_id" uuid;--> statement-breakpoint
ALTER TABLE "items" ADD COLUMN "serial" integer;--> statement-breakpoint
UPDATE "items" i SET "serial" = n.rn FROM (SELECT id, row_number() OVER (PARTITION BY board_id ORDER BY created_at, id) AS rn FROM "items") n WHERE n.id = i.id;--> statement-breakpoint
ALTER TABLE "items" ALTER COLUMN "serial" SET NOT NULL;--> statement-breakpoint
ALTER TABLE "items" ADD COLUMN "updated_by_user_id" uuid;--> statement-breakpoint
ALTER TABLE "items" ADD COLUMN "trashed_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "activity_log" ADD COLUMN "undone_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "activity_log" ADD COLUMN "undone_by_user_id" uuid;--> statement-breakpoint
ALTER TABLE "files" ADD COLUMN "column_id" uuid;--> statement-breakpoint
ALTER TABLE "templates" ADD COLUMN "account_id" uuid;--> statement-breakpoint
ALTER TABLE "templates" ADD COLUMN "created_by_user_id" uuid;--> statement-breakpoint
ALTER TABLE "templates" ADD COLUMN "created_at" timestamp with time zone DEFAULT now() NOT NULL;--> statement-breakpoint
ALTER TABLE "update_reactions" ADD CONSTRAINT "update_reactions_update_id_updates_id_fk" FOREIGN KEY ("update_id") REFERENCES "public"."updates"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "update_reactions" ADD CONSTRAINT "update_reactions_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "update_reactions_uq" ON "update_reactions" USING btree ("update_id","user_id","emoji");--> statement-breakpoint
CREATE INDEX "update_reactions_update_idx" ON "update_reactions" USING btree ("update_id");--> statement-breakpoint
INSERT INTO "update_reactions" ("update_id", "user_id", "emoji", "created_at") SELECT "update_id", "user_id", chr(128077), "created_at" FROM "update_likes";--> statement-breakpoint
ALTER TABLE "items" ADD CONSTRAINT "items_parent_item_id_items_id_fk" FOREIGN KEY ("parent_item_id") REFERENCES "public"."items"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "items" ADD CONSTRAINT "items_updated_by_user_id_users_id_fk" FOREIGN KEY ("updated_by_user_id") REFERENCES "public"."users"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "activity_log" ADD CONSTRAINT "activity_log_undone_by_user_id_users_id_fk" FOREIGN KEY ("undone_by_user_id") REFERENCES "public"."users"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "files" ADD CONSTRAINT "files_column_id_columns_id_fk" FOREIGN KEY ("column_id") REFERENCES "public"."columns"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "templates" ADD CONSTRAINT "templates_account_id_accounts_id_fk" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "templates" ADD CONSTRAINT "templates_created_by_user_id_users_id_fk" FOREIGN KEY ("created_by_user_id") REFERENCES "public"."users"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "items_parent_idx" ON "items" USING btree ("parent_item_id");--> statement-breakpoint
CREATE UNIQUE INDEX "items_board_serial_uq" ON "items" USING btree ("board_id","serial");--> statement-breakpoint
CREATE INDEX "templates_account_idx" ON "templates" USING btree ("account_id");--> statement-breakpoint
CREATE INDEX "activity_log_board_idx" ON "activity_log" USING btree ("board_id","created_at");