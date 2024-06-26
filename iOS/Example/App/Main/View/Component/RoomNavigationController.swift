//
//  RoomNavigationController.swift
//  DemoApp
//
//  Created by janejntang on 2023/12/11.
//

import Foundation
import UIKit

class RoomNavigationController: UINavigationController {
    override init(rootViewController: UIViewController) {
        super.init(rootViewController: rootViewController)
        interactivePopGestureRecognizer?.isEnabled = false
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        guard let supportedInterfaceOrientations = topViewController?.supportedInterfaceOrientations as? UIInterfaceOrientationMask
        else { return .portrait }
        return supportedInterfaceOrientations
    }
    override var shouldAutorotate: Bool {
        guard let shouldAutorotate = topViewController?.shouldAutorotate else { return false }
        return shouldAutorotate
    }
}
