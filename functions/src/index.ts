import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();

/**
 * Callable Cloud Function:
 *  - Name: fetchEmailReceipts
 *  - Erwartet:
 *      { fromDate?: string, allowDuplicates?: boolean }
 *  - Liefert:
 *      { receipts: Array<{ messageId, storeName, dateTime, total }> }
 *
 * Aktuell: MOCK-Daten.
 * Später: Hier kannst du deine echte Gmail-Logik einbauen.
 */
export const fetchEmailReceipts = functions.https.onCall(
  async (request: functions.https.CallableRequest<any>) => {
    // request.auth: Firebase Auth Context
    if (!request.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "User must be authenticated"
      );
    }

    const uid = request.auth.uid;

    const fromDateStr = request.data?.fromDate as string | undefined;
    const allowDuplicates = !!request.data?.allowDuplicates;

    let fromDate: Date | null = null;
    if (fromDateStr) {
      try {
        fromDate = new Date(fromDateStr);
      } catch {
        fromDate = null;
      }
    }

    const now = new Date();
    const baseReceipts = [
      {
        messageId: "mock-rewe-" + uid,
        storeName: "REWE",
        dateTime: new Date(now.getTime() - 1 * 24 * 60 * 60 * 1000),
        total: 0,
      },
      {
        messageId: "mock-aldi-" + uid,
        storeName: "ALDI",
        dateTime: new Date(now.getTime() - 2 * 24 * 60 * 60 * 1000),
        total: 0,
      },
      {
        messageId: "mock-lidl-" + uid,
        storeName: "LIDL",
        dateTime: new Date(now.getTime() - 3 * 24 * 60 * 60 * 1000),
        total: 0,
      },
    ];

    const filtered = baseReceipts.filter((r) => {
      if (!fromDate) return true;
      return r.dateTime >= fromDate;
    });

    const receipts = filtered.map((r) => ({
      messageId: r.messageId,
      storeName: r.storeName,
      dateTime: r.dateTime.toISOString(),
      total: r.total,
    }));

    void allowDuplicates; // aktuell noch nicht genutzt

    return {receipts};
  }
);
