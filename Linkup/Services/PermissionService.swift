import CoreLocation
import Foundation
import UserNotifications

final class PermissionService: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func requestOnboardingPermissions() {
        locationManager.requestWhenInUseAuthorization()
        NotificationService.shared.requestAuthorizationAndRegister()
    }
}
