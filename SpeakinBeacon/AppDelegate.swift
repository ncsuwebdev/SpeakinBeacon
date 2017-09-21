//
//  AppDelegate.swift
//  SpeakinBeacon
//
//  Created by Dan Waller on 9/5/17.
//  Copyright © 2017 NC State. All rights reserved.
//

import UIKit
import UserNotifications
import CloudKit


@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    var window: UIWindow?
    let center = UNUserNotificationCenter.current()
    var notificationActionURL = ""
    var beaconArray = [[String:String]]()
    var beaconUUID = ""
    var baseURL = ""
    let container:CKContainer
    let publicDB : CKDatabase
    var predicate = NSPredicate()


    required override init() {
        container = CKContainer.default()
        publicDB = container.publicCloudDatabase
        super.init()
    }
    
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        //Load initial value into app setting for beacon file location.  This will cause app to load from CloudKit.
        let defaults:UserDefaults = UserDefaults.standard
        var appDefaults = Dictionary<String, AnyObject>()
        appDefaults["baseURL"] = "https://storage.googleapis.com/speakin-beacon" as AnyObject
        defaults.register(defaults: appDefaults)
        defaults.synchronize()
        
        registerForPushNotifications(application: application)
        self.loadBeaconInfo()
        
        return true
    }
    
    func getURI(_ completion:@escaping ()->Void) {
        //Check app settings for beacon base URL first. If nil or empty, go to iCloud settings.
        guard let tempURL = UserDefaults.standard.string(forKey: "baseURL"), !tempURL.isEmpty else {
            let predicate = NSPredicate(format: "TRUEPREDICATE", argumentArray: [])
            let query = CKQuery(recordType: "URI", predicate: predicate)
            
            publicDB.perform(query, inZoneWith: nil) { results, error in
                if error != nil {
                    print(error!)
                } else {
                    for item in results! {
                        self.baseURL = item .object(forKey: "base") as! String
                    }
                    completion()
                }
            }
            return
        }
        self.baseURL = tempURL
        //check the entered baseURL for a trailing slash and add one if needed.  This normalizes the URL for future use.
        if self.baseURL.characters.last! != "/" {
            self.baseURL += "/"
        }
        completion()
    }
    
    
    func loadBeaconInfo() {
        self.getURI({() in
            
            //Load beacons from custom URL
            guard let data = self.readBeaconFile() else {
                //Load beacons from iCloud
                self.getBeaconsCloudKit({() in
                })
                return
            }
            let dataArr = data.components(separatedBy:"\n")
            for entry:String in dataArr {
                var beacon = [String:String]()
                let temp:[String] = entry.components(separatedBy:",")
                if temp.count == 4 {
                    beacon["name"] = temp[0]
                    beacon["uuid"] = temp[1]
                    beacon["major"] = temp[2]
                    beacon["minor"] = temp[3]
                    self.beaconArray.append(beacon)
                }
            }
            self.beaconUUID = self.beaconArray[0]["uuid"]!
        })
    }
    
    //iBeacon support
    //Load beacon list from iCloud
    func getBeaconsCloudKit(_ completion:@escaping ()->Void) {
        let predicate = NSPredicate(format: "TRUEPREDICATE", argumentArray: [])
        let query = CKQuery(recordType: "Beacon", predicate: predicate)
        
        publicDB.perform(query, inZoneWith: nil) { results, error in
            if error != nil {
                print(error!)
            } else if results == nil {
                NotificationCenter.default.post(name: Notification.Name("noBeacons"), object: nil)
                completion()
            } else {
                for item in results! {
                    var beacon = [String:String]()
                    beacon["name"] = item .object(forKey: "Name") as! String?
                    beacon["uuid"] = item .object(forKey: "UUID") as! String?
                    beacon["major"] = item .object(forKey: "Major") as! String?
                    beacon["minor"] = item .object(forKey: "Minor") as! String?
                    self.beaconArray.append(beacon)
                }
                guard !self.beaconArray.isEmpty else {
                    NotificationCenter.default.post(name: Notification.Name("noBeacons"), object: nil)
                    completion()
                    return
                }
                self.beaconUUID = self.beaconArray[0]["uuid"]!
                completion()
            }
        }
    }
    
    //Loads beacon list from custom URL
    func readBeaconFile()->String!{
        if let url = URL(string:self.baseURL + "beacons.txt") {
            do {
                let contents = try String(contentsOf: url, encoding: .utf8)
                return contents
            } catch {
                print("Beacons file not available")
                return nil
            }
        } else {
            print("String was not a URL")
            return nil
        }
    }
    
    
    func registerForPushNotifications(application: UIApplication) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { (granted, error) in
            // Enable or disable features based on authorization
            if granted {
                print("Approval granted to send notifications")
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        
        completionHandler([.alert,.sound])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            // The user launched the app
        }
        else if response.actionIdentifier == "viewSite" {
            let url = URL(string:self.notificationActionURL)
            UIApplication.shared.open(url!, options: [:], completionHandler: nil)
        }
        completionHandler()
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        
        completionHandler(UIBackgroundFetchResult.newData)
    }


    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }


}

