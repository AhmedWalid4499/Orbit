// Joshu's admin page server (see handler.ts). Uses the service role, which never leaves Supabase.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { handle } from "./handler.ts";

Deno.serve((req) => handle(req, createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!)));
