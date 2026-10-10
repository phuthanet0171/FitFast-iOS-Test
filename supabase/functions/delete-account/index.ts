// Deletes the signed-in user's account and all of their data.
//
// Deploy: Supabase Dashboard -> Edge Functions -> Deploy a new function ->
// name it "delete-account" and paste this file, or with the CLI:
//   supabase functions deploy delete-account
//
// The caller is identified only from their own access token; the service
// role key never leaves the server.
import { createClient } from "npm:@supabase/supabase-js@2";

const jsonHeaders = { "Content-Type": "application/json" };

// Tables keyed by user_id. profiles is keyed by id and removed last.
const userTables = [
  "meal_entries",
  "daily_nutrition_records",
  "weight_records",
  "fasting_sessions",
  "fasting_settings",
  "user_food_preferences",
];

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), {
      status: 405,
      headers: jsonHeaders,
    });
  }

  const token = (request.headers.get("Authorization") ?? "")
    .replace(/^Bearer\s+/i, "")
    .trim();
  if (!token) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: jsonHeaders,
    });
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  // Only a valid user access token resolves to a user; the publishable key
  // or an expired token does not.
  const { data: userData, error: userError } = await admin.auth.getUser(token);
  const user = userData?.user;
  if (userError || !user) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: jsonHeaders,
    });
  }

  for (const table of userTables) {
    const { error } = await admin.from(table).delete().eq("user_id", user.id);
    // A table that does not exist in this project is skipped.
    if (error && error.code !== "42P01") {
      return new Response(
        JSON.stringify({ error: "delete_failed", table }),
        { status: 500, headers: jsonHeaders },
      );
    }
  }
  const { error: profileError } = await admin
    .from("profiles")
    .delete()
    .eq("id", user.id);
  if (profileError && profileError.code !== "42P01") {
    return new Response(
      JSON.stringify({ error: "delete_failed", table: "profiles" }),
      { status: 500, headers: jsonHeaders },
    );
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) {
    return new Response(JSON.stringify({ error: "delete_failed" }), {
      status: 500,
      headers: jsonHeaders,
    });
  }

  return new Response(JSON.stringify({ deleted: true }), {
    status: 200,
    headers: jsonHeaders,
  });
});
