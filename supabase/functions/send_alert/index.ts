import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const TWILIO_ACCOUNT_SID  = Deno.env.get("TWILIO_ACCOUNT_SID")!;
const TWILIO_API_KEY      = Deno.env.get("TWILIO_API_KEY")!;
const TWILIO_API_SECRET   = Deno.env.get("TWILIO_AUTH_TOKEN")!;
const TWILIO_FROM_NUMBER  = Deno.env.get("TWILIO_FROM_NUMBER")!;
const SUPABASE_URL        = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

serve(async (req) => {

  // ── 1. Parse request ──────────────────────────────────────────────
  const { region, message } = await req.json();

  if (!region || !message) {
    return new Response(
      JSON.stringify({ error: "Missing region or message" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  // ── 2. Supabase client (service role bypasses RLS) ────────────────
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

  // ── 3. Fetch active subscribers for this region ───────────────────
  const { data: subscribers, error: fetchError } = await supabase
    .from("subscribers")
    .select("id, phone, region")
    .eq("region", region)
    .eq("status", "active");

  if (fetchError) {
    return new Response(
      JSON.stringify({ error: fetchError.message }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  if (!subscribers || subscribers.length === 0) {
    return new Response(
      JSON.stringify({ sent: 0, message: "No active subscribers for this region" }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  }

  // ── 4. Send SMS via Twilio + log each result ──────────────────────
  const results = await Promise.all(
    subscribers.map(async (sub) => {
      let status = "sent";
      let twilio_sid = null;
      let error_message = null;

      try {
        const twilioRes = await fetch(
          `https://api.twilio.com/2010-04-01/Accounts/${TWILIO_ACCOUNT_SID}/Messages.json`,
          {
            method: "POST",
            headers: {
              "Authorization": "Basic " + btoa(`${TWILIO_API_KEY}:${TWILIO_API_SECRET}`),
              "Content-Type": "application/x-www-form-urlencoded",
            },
            body: new URLSearchParams({
              From: TWILIO_FROM_NUMBER,
              To:   sub.phone,
              Body: `[Burn Notice] ${message}`,
            }),
          }
        );

        const twilioData = await twilioRes.json();

        if (!twilioRes.ok) {
          status = "failed";
          error_message = twilioData.message ?? "Twilio error";
        } else {
          twilio_sid = twilioData.sid;
        }

      } catch (err) {
        status = "failed";
        error_message = err.message;
      }

      // ── 5. Log to sms_logs ────────────────────────────────────────
      await supabase.from("sms_logs").insert({
        phone:         sub.phone,
        region:        sub.region,
        message,
        status,
        twilio_sid,
        error_message,
        sent_at:       new Date().toISOString(),
      });

      return { phone: sub.phone, status, twilio_sid, error_message };
    })
  );

  // ── 6. Return summary ─────────────────────────────────────────────
  const sent   = results.filter(r => r.status === "sent").length;
  const failed = results.filter(r => r.status === "failed").length;

  return new Response(
    JSON.stringify({ sent, failed, results }),
    { status: 200, headers: { "Content-Type": "application/json" } }
  );
});