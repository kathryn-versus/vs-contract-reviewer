import { NextRequest, NextResponse } from 'next/server';
import { sendReviewNotification } from '@/lib/gmail/client';

// Recipients: kathryn@vsnyc.tv (active). samantha@vsnyc.tv is commented out
// during testing — uncomment NOTIFY_EMAIL_SECONDARY when ready to go live.
// Brief §7.
export async function POST(req: NextRequest) {
  try {
    const body = await req.json();

    const recipients = [process.env.NOTIFY_EMAIL_PRIMARY, process.env.NOTIFY_EMAIL_SECONDARY].filter(
      (v): v is string => Boolean(v)
    );

    await sendReviewNotification({ ...body, to: recipients });
    return NextResponse.json({ ok: true, sentTo: recipients });
  } catch (err) {
    console.error('gmail/notify failed', err);
    // Notification failures should never block the review flow — log and
    // return 200-with-warning rather than surfacing an error to the user.
    return NextResponse.json({ ok: false, warning: err instanceof Error ? err.message : 'Notify failed' });
  }
}
