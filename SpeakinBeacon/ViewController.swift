//
//  ViewController.swift
//  SpeakinBeacon
//
//  Created by Dan Waller on 9/5/17.
//  Copyright © 2017 NC State. All rights reserved.
//

import UIKit
import CoreLocation
import UserNotifications
import CloudKit
import SafariServices
import CoreBluetooth


class ViewController: UIViewController, CLLocationManagerDelegate, SFSafariViewControllerDelegate, UIWebViewDelegate, CBPeripheralManagerDelegate {
    
    var locationManager:CLLocationManager!
    let container:CKContainer
    let publicDB : CKDatabase
    var predicate = NSPredicate()
    var beaconArray = [[String:String]]()
    var beaconCategory = ""
    var beaconUUID = ""
    var beaconMajor = ""
    var beaconMinor = ""
    var lastBeaconMinor = ""
    var lastPopupBeaconMinor = ""
    var lastBuildingBeaconMinor = ""
    var lastExhibitBeaconMinor = ""
    var payloadURL = URL(string:"")
    var assetImageURL = URL(string:"")
    var assetText = ""
    var baseURL = ""
    var myBTManager: CBPeripheralManager?
    let appDelegate = UIApplication.shared.delegate as! AppDelegate
    
    //Sample URL format:
    //format: <base url>/<UUID>/<Major>/<Minor>/index.html
    //https://storage.googleapis.com/your-project/B7D1027D-6788-416E-994F-EA11075F1765/3000/3002/index.html
    
    
    @IBOutlet var messageView:UIWebView!
    @IBOutlet var image:UIImageView!
    @IBOutlet var activityIndicator:UIActivityIndicatorView!
    
    required init?(coder aDecoder: NSCoder) {
        container = CKContainer.default()
        publicDB = container.publicCloudDatabase
        super.init(coder: aDecoder)
    }
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if myBTManager?.state == CBManagerState.poweredOff {
            let alert = UIAlertController(title: "Warning", message: "Bluetooth must be active to use this app with beacons.  Please turn on Bluetooth in Settings.", preferredStyle: .alert)
            let okAction = UIAlertAction(title: "OK", style: UIAlertActionStyle.default, handler: {(action: UIAlertAction!) in })
            alert.addAction(okAction)
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    func loadBeaconData() {
        messageView.delegate = self
        print("Launch")
        self.beaconArray = appDelegate.beaconArray
        self.beaconUUID = appDelegate.beaconUUID
        self.baseURL = appDelegate.baseURL
        let homeURL = self.baseURL + self.beaconUUID + "/index.html"
        var request = URLRequest(url: URL(string:homeURL)!, cachePolicy:NSURLRequest.CachePolicy.reloadIgnoringLocalAndRemoteCacheData)
        request.setValue("text/html; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        self.messageView.loadRequest(request)
        self.startScanning()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        NotificationCenter.default.addObserver(self, selector: #selector(ViewController.loadBeaconData), name: NSNotification.Name("Launch"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(ViewController.noBeaconAlert), name: NSNotification.Name("noBeacons"), object: nil)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        myBTManager = CBPeripheralManager(delegate: self, queue: nil, options: nil)
        
        locationManager = CLLocationManager()
        locationManager.delegate = self
        locationManager.requestAlwaysAuthorization()
        self.activityIndicator.isHidden = true
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func noBeaconAlert() {
        let alertController = UIAlertController(title: "Alert", message: "No beacon data is available.", preferredStyle: UIAlertControllerStyle.alert)
        
        let okAction = UIAlertAction(title: "OK", style: UIAlertActionStyle.default)
        {
            (result : UIAlertAction) -> Void in
            print("You pressed OK")
        }
        alertController.addAction(okAction)
        self.present(alertController, animated: true, completion: nil)
    }
    
    @IBAction func launchWeb() {
        let url = URL(string:"https://www.ncsu.edu/")
        let sfc = SFSafariViewController(url: url!)
        sfc.delegate = self
        self.present(sfc, animated: true, completion: nil)
    }
    
    //MARK: iBeacon support
    func getURI(_ completion:@escaping ()->Void) {
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
    }
    
    
    func getBeacons(_ completion:@escaping ()->Void) {
        let predicate = NSPredicate(format: "TRUEPREDICATE", argumentArray: [])
        let query = CKQuery(recordType: "Beacon", predicate: predicate)
        
        publicDB.perform(query, inZoneWith: nil) { results, error in
            if error != nil {
                print(error!)
            } else {
                for item in results! {
                    var beacon = [String:String]()
                    beacon["name"] = item .object(forKey: "Name") as! String?
                    beacon["category"] = item .object(forKey: "Category") as! String?
                    beacon["uuid"] = item .object(forKey: "UUID") as! String?
                    beacon["major"] = item .object(forKey: "Major") as! String?
                    beacon["minor"] = item .object(forKey: "Minor") as! String?
                    self.beaconArray.append(beacon)
                }
                self.beaconUUID = self.beaconArray[0]["uuid"]!
                completion()
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("changed auth")
    }
    
    func startScanning() {
        for entry in beaconArray {
            print("scan")
            let localBeaconRegion = CLBeaconRegion(proximityUUID:UUID(uuidString: entry["uuid"]!)!, major: UInt16(entry["major"]!)!, minor: UInt16(entry["minor"]!)!, identifier: entry["name"]!)
            let mainBeaconRegion = CLBeaconRegion(proximityUUID: UUID(uuidString: entry["uuid"]!)!, identifier: "mainRegion")
            mainBeaconRegion.notifyOnEntry = true
            locationManager.startMonitoring(for: mainBeaconRegion)
            locationManager.startRangingBeacons(in: localBeaconRegion)
        }
        
    }
    
    func stopScanning() {
        print("Stop Scanning")
        for entry in beaconArray {
            let localBeaconRegion = CLBeaconRegion(proximityUUID:UUID(uuidString: entry["uuid"]!)!, major: UInt16(entry["major"]!)!, minor: UInt16(entry["minor"]!)!, identifier: entry["name"]!)
            let mainBeaconRegion = CLBeaconRegion(proximityUUID: UUID(uuidString: entry["uuid"]!)!, identifier: "mainRegion")
            mainBeaconRegion.notifyOnEntry = false
            locationManager.stopMonitoring(for: mainBeaconRegion)
            locationManager.stopRangingBeacons(in: localBeaconRegion)
        }
        
    }
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        if let beaconRegion = region as? CLBeaconRegion {
            self.sendRegionNotification(message:"Welcome to the Speakin Beacon Demo.  Check out all of our exhibits and features!",image: "wolves",id:"regionEntry")
        }
        
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        if let beaconRegion = region as? CLBeaconRegion {
            //locationManager.stopRangingBeacons(in: beaconRegion)
            self.sendRegionNotification(message:"Thanks for using the Speakin Beacon Demo.",image: "science",id:"regionExit")
            self.lastExhibitBeaconMinor = ""
            self.lastPopupBeaconMinor = ""
            self.lastBuildingBeaconMinor = ""
            self.resetScreen()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didRangeBeacons beacons: [CLBeacon], in region: CLBeaconRegion) {
        
        if beacons.count > 0 {
            let tempName = String(format: "%d",beacons[0].minor.intValue)
            let tempArray = beaconArray.filter{$0["minor"] == tempName}
            self.beaconCategory = tempArray[0]["category"]!
            self.beaconMajor = tempArray[0]["major"]!
            self.beaconMinor = tempArray[0]["minor"]!
            updateDistance(beacons[0].proximity)
        }
    }
    
    func updateDistance(_ distance: CLProximity) {
        UIView.animate(withDuration: 0.8) {
            switch distance {
            case .unknown:
                //self.dist = "unknown"
                break
            case .far:
                break
            case .near:
                if self.beaconMajor == "1000" {
                    if self.beaconMinor != self.lastBuildingBeaconMinor {
                        self.updateView()
                    }
                    self.lastBuildingBeaconMinor = self.beaconMinor
                } else if self.beaconMajor == "2000" {
                    if self.beaconMinor != self.lastPopupBeaconMinor {
                        let dist =  "near"
                        //self.updateView()
                        self.sendNotification(distance: dist, major: self.beaconMajor)
                    }
                    self.lastPopupBeaconMinor = self.beaconMinor
                } else if self.beaconMajor == "3000" {
                    if self.beaconMinor != self.lastExhibitBeaconMinor {
                        self.updateView()
                    }
                    self.lastExhibitBeaconMinor = self.beaconMinor
                }
            case .immediate:
                break
            }
        }
    }
    
    func resetScreen() {
        let homeURL = self.baseURL + self.beaconUUID + "/index.html"
        var request = URLRequest(url: URL(string:homeURL)!, cachePolicy:NSURLRequest.CachePolicy.reloadIgnoringLocalAndRemoteCacheData)
        request.setValue("text/html; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        self.messageView.loadRequest(request)
    }
    
    //MARK: Notifications
    func getGaeCloudContent(_ completion:@escaping()->Void) {
        let contentURL = self.baseURL + self.beaconUUID + "/" + self.beaconMajor + "/" + self.beaconMinor + "/"
        let imageCloudURL = URL(string:"\(contentURL)image.png")
        let dataURL = URL(string:"\(contentURL)index.html")
        let notificationDataURL = URL(string: "\(contentURL)message.txt")
        var tempData = ""
        var imageExists = false
        imageExists = ((try? imageCloudURL?.checkResourceIsReachable()) ?? false)!
        if (imageExists) {
            let task = URLSession.shared.dataTask(with: imageCloudURL!, completionHandler: { data, response, error in
                
                
                let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let fileURL = documentsURL.appendingPathComponent("\(self.beaconMinor).png")
                if ((error) == nil) {
                    do {
                        try UIImagePNGRepresentation(UIImage(data: (data)!)!)?.write(to: fileURL)
                    } catch {print ("Image error") }
                }
                
                DispatchQueue.main.async {
                    self.assetImageURL = fileURL
                    completion()
                }
            })
            task.resume()
        }
        do {
            tempData = try String(contentsOf: notificationDataURL!)
            self.assetText = tempData
        }
        catch let error {
            print("Text Error: \(error)")
        }
        self.payloadURL = dataURL
        completion()
    }
    
    
    func sendNotification(distance: String, major: String) {
        self.getGaeCloudContent({() in
            let content = UNMutableNotificationContent()
            content.title = "Speakin Beacon Demo"
            content.subtitle = "Proximity Notificaion"
            content.body = self.assetText
            content.sound = UNNotificationSound.default()
            content.categoryIdentifier = ""
            
            do {
                let url = self.assetImageURL
                let attachment = try UNNotificationAttachment(identifier: "logo", url: url!, options: nil)
                content.attachments = [attachment]
                
                if major == "2000" {
                    let appDelegate = UIApplication.shared.delegate as! AppDelegate
                    appDelegate.notificationActionURL = self.baseURL + self.beaconUUID + "/" + self.beaconMajor + "/" + self.beaconMinor + "/index.html"
                    let action = UNNotificationAction(identifier: "viewSite", title: "Visit Web Site", options: [])
                    let category = UNNotificationCategory(identifier: "viewCategory", actions: [action], intentIdentifiers: [], options: [])
                    UNUserNotificationCenter.current().setNotificationCategories([category])
                    content.categoryIdentifier = "viewCategory"
                }
            } catch {
                print("The attachment was not loaded.")
            }
            
            
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
            let requestIdentifier = self.beaconMajor
            
            let request = UNNotificationRequest(identifier: requestIdentifier, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request) {
                (error) in
                if let error = error {
                    print("Problem adding notification: \(error.localizedDescription)")
                }
                else {
                    // Set icon
                    print("added")
                }
            }
        })
    }
    
    func sendRegionNotification(message:String, image:String, id:String) {
        let content = UNMutableNotificationContent()
        content.title = "Speakin Beacon Demo"
        content.subtitle = "Region Notification"
        content.body = message
        content.sound = UNNotificationSound.default()
        
        if let path = Bundle.main.path(forResource: image, ofType: "jpg") {
            let url = URL(fileURLWithPath: path)
            
            do {
                let attachment = try UNNotificationAttachment(identifier: "logo", url: url, options: nil)
                content.attachments = [attachment]
            } catch {
                print("The attachment was not loaded.")
            }
        }
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let requestIdentifier = id
        let request = UNNotificationRequest(identifier: requestIdentifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) {
            (error) in
            if let error = error {
                print("Problem adding notification: \(error.localizedDescription)")
            }
            else {
                // Set icon
                print("added region notification")
            }
        }
    }
    
    func updateView() {
        self.getGaeCloudContent({() in
            var request = URLRequest(url: self.payloadURL!, cachePolicy:NSURLRequest.CachePolicy.reloadIgnoringLocalAndRemoteCacheData)
            request.setValue("text/html; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            self.messageView.loadRequest(request)
        })
    }
    
    
    //MARK: WebView Delegate
    func webView(_ webView: UIWebView, shouldStartLoadWith request: URLRequest, navigationType: UIWebViewNavigationType) -> Bool {
        if navigationType == UIWebViewNavigationType.linkClicked {
            if (request.url?.host! == "googleapis.com"){
                self.activityIndicator.isHidden = false
                self.activityIndicator.startAnimating()
                return true
            } else {
                let sfc = SFSafariViewController(url: request.url!)
                sfc.delegate = self
                self.present(sfc, animated: true, completion: nil)
                return false
            }
        }
        return true
    }
    
    func webViewDidFinishLoad(_ webView: UIWebView) {
        self.activityIndicator.stopAnimating()
        self.activityIndicator.isHidden = true
    }
    
    func webView(_ webView: UIWebView, didFailLoadWithError error: Error) {
        print("Webview error: \(error)")
        self.messageView.loadRequest(URLRequest(url: URL(fileURLWithPath: Bundle.main.path(forResource: "intro", ofType: "html")!)))
        //self.resetScreen()
    }
    
    
    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        controller.dismiss(animated: true, completion: nil)
    }
    
    
}

