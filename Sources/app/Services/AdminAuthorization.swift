//
//  AdminAuthorization.swift
//  BootstrapMate
//
//  Asks an administrator to authenticate when the user saves settings. Each
//  Save prompts afresh and the authorization is freed once the save ends, so
//  the window never stays unlocked and a standard user cannot change machine
//  settings without an administrator's name and password.
//

import Foundation
import Security
import BootstrapMateCore

/// One administrator authorization, held only for the duration of a save.
@MainActor
final class AdminAuthorization {
    private var authRef: AuthorizationRef?

    /// The external form the helper accepts.
    let externalForm: Data

    private init(authRef: AuthorizationRef, externalForm: Data) {
        self.authRef = authRef
        self.externalForm = externalForm
    }

    /// Shows the system's administrator prompt. Returns nil when the user
    /// cancels or the credentials do not belong to an administrator.
    static func authorize() -> AdminAuthorization? {
        var ref: AuthorizationRef?
        guard AuthorizationCreate(nil, nil, [], &ref) == errAuthorizationSuccess, let ref else { return nil }

        let status = kHelperAdminRight.withCString { name -> OSStatus in
            var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { itemPointer in
                var rights = AuthorizationRights(count: 1, items: itemPointer)
                return AuthorizationCopyRights(ref, &rights, nil, [.interactionAllowed, .extendRights, .preAuthorize], nil)
            }
        }
        guard status == errAuthorizationSuccess else {
            AuthorizationFree(ref, [])
            return nil
        }

        var form = AuthorizationExternalForm()
        guard AuthorizationMakeExternalForm(ref, &form) == errAuthorizationSuccess else {
            AuthorizationFree(ref, [.destroyRights])
            return nil
        }
        return AdminAuthorization(authRef: ref, externalForm: withUnsafeBytes(of: &form) { Data($0) })
    }

    /// Discards the authorization, so the next save needs a new prompt.
    func free() {
        if let authRef {
            AuthorizationFree(authRef, [.destroyRights])
        }
        authRef = nil
    }
}
