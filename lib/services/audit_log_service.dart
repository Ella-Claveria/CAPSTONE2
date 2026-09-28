import 'package:cloud_functions/cloud_functions.dart';

/// Every action the Admin Portal's Audit Log can record. Kept in sync with
/// PRE_AUTH_ACTIONS/AUTHENTICATED_ACTIONS in functions/index.js — the
/// Cloud Function is the real source of truth (it's what actually decides
/// what's loggable), this is just the matching client-side list so typos
/// fail loudly instead of silently no-op-ing server-side.
abstract final class AuditAction {
  static const loginSuccess = 'LOGIN_SUCCESS';
  static const loginFailed = 'LOGIN_FAILED';
  static const logout = 'LOGOUT';
  static const passwordResetRequested = 'PASSWORD_RESET_REQUESTED';
  static const approveFarmer = 'APPROVE_FARMER';
  static const rejectFarmer = 'REJECT_FARMER';
  static const updateBaselinePrice = 'UPDATE_BASELINE_PRICE';
  static const deleteBaselinePrice = 'DELETE_BASELINE_PRICE';
  static const importBaselinePrices = 'IMPORT_BASELINE_PRICES';
  static const warnSeller = 'WARN_SELLER';
  static const suspendListing = 'SUSPEND_LISTING';
  static const removeListing = 'REMOVE_LISTING';
  static const suspendFarmer = 'SUSPEND_FARMER';
  static const banFarmer = 'BAN_FARMER';
  static const exportReport = 'EXPORT_REPORT';

  static const all = [
    loginSuccess,
    loginFailed,
    logout,
    passwordResetRequested,
    approveFarmer,
    rejectFarmer,
    updateBaselinePrice,
    deleteBaselinePrice,
    importBaselinePrices,
    warnSeller,
    suspendListing,
    removeListing,
    suspendFarmer,
    banFarmer,
    exportReport,
  ];

  /// The two actions that can happen before anyone is signed in — a failed
  /// password attempt, or a password-reset request. Every other action
  /// requires an authenticated caller (see logAuditEvent in
  /// functions/index.js).
  static const preAuth = {loginFailed, passwordResetRequested};
}

/// One reusable helper for the whole Admin Portal audit trail — every admin
/// action funnels through [log] instead of writing to Firestore directly.
///
/// The actual write happens server-side, in the `logAuditEvent` Cloud
/// Function: that's the only place that can see the caller's real IP
/// address, and the only place `adminId`/`adminEmail` can be trusted
/// (pulled from the verified auth token, never from what the client
/// claims). Firestore rules deny every client write to `audit_logs`
/// outright, so this call is the sole path in.
///
/// Logging is best-effort and must never block or fail the admin action it
/// describes — approving a farmer must succeed even if the audit write
/// fails (offline, function cold-start timeout, etc), so every call here
/// is fire-and-forget with its own try/catch.
class AuditLogService {
  static final _functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  /// Logs an authenticated admin action (everything except a failed login
  /// or a password-reset request — see [logPreAuth] for those). [details]
  /// should be a short, human-readable summary, e.g. "Rice: ₱45.00 →
  /// ₱48.00" or "Approved farmer Juan Dela Cruz" — it's shown as-is in the
  /// Audit Log table's Details column.
  static Future<void> log(String action, String details) async {
    try {
      await _functions.httpsCallable('logAuditEvent').call({
        'action': action,
        'details': details,
      });
    } catch (_) {
      // Best-effort — never let a logging failure surface to the admin or
      // block the action that triggered it.
    }
  }

  /// Logs a failed login attempt or a password-reset request — the two
  /// actions that can happen before anyone is signed in, so there's an
  /// attempted email instead of a verified admin identity.
  static Future<void> logPreAuth(String action, {required String email, String? details}) async {
    try {
      await _functions.httpsCallable('logAuditEvent').call({
        'action': action,
        'email': email,
        'details': ?details,
      });
    } catch (_) {
      // Best-effort, same reasoning as log() above.
    }
  }
}
