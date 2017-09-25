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
        //Check that Bluetooth is enabled on the device
        if myBTManager?.state == CBManagerState.poweredOff {
            let alert = UIAlertController(title: "Warning", message: "Bluetooth must be active to use this app with beacons.  Please turn on Bluetooth in Settings.", preferredStyle: .alert)
            let okAction = UIAlertAction(title: "OK", style: UIAlertActionStyle.default, handler: {(action: UIAlertAction!) in })
            alert.addAction(okAction)
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    //Load the beacon list and main UUID.  Load the welcome page of the app
    func loadBeaconData() {
        messageView.delegate = self
        self.beaconArray = appDelegate.beaconArray
        self.beaconUUID = appDelegate.beaconUUID
        self.baseURL = appDelegate.baseURL
        //check the entered baseURL for a trailing slash and add one if needed.  This normalizes the URL for future use.
        if self.baseURL.characters.last! != "/" {
            self.baseURL += "/"
        }
        let homeURL = self.baseURL + "index.html"
        print("URL: \(homeURL)")
        var request = URLRequest(url: URL(string:homeURL)!, cachePolicy:NSURLRequest.CachePolicy.reloadIgnoringLocalAndRemoteCacheData)
        request.setValue("text/html; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        
        //Check if home page URL exists otherwise load bundled intro.html
        self.fileExistsAt(url: URL(string: homeURL)!, completion: ({(exists:Bool) in
            if exists {
                DispatchQueue.main.async {
                    self.messageView.loadRequest(request)
                }
            } else {
                print("Webview error")
                DispatchQueue.main.async {
                    self.messageView.loadRequest(URLRequest(url: URL(fileURLWithPath: Bundle.main.path(forResource: "intro", ofType: "html")!)))
                }
            }
        }))
        self.startScanning()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        NotificationCenter.default.addObserver(self, selector: #selector(ViewController.loadBeaconData), name: NSNotification.Name("Launch"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(ViewController.noBeaconAlert), name: NSNotification.Name("noBeacons"), object: nil)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        myBTManager = CBPeripheralManager(delegate: self, queue: nil, options: nil)
        
        locationManager = CLLocationManager()
        locationManager.delegate = self
        locationManager.requestAlwaysAuthorization()
        self.activityIndicator.isHidden = true
        self.loadBeaconData()
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
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("changed auth")
    }
    
    //Set up beacon regions.  For this example we are setting a region for every beacon, but you don't have to do that.  There is a limit of 20 regions that can be defined.
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
    
    
    //Region monitoring only detects entry and exit.
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        if let beaconRegion = region as? CLBeaconRegion {
            self.sendRegionNotification(message:"Welcome to the Speakin Beacon Demo.  Check out all of our exhibits and features!",image: "wolves",id:"regionEntry")
        }
        
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        if let beaconRegion = region as? CLBeaconRegion {
            self.sendRegionNotification(message:"Thanks for using the Speakin Beacon Demo.",image: "science",id:"regionExit")
            self.lastExhibitBeaconMinor = ""
            self.lastPopupBeaconMinor = ""
            self.lastBuildingBeaconMinor = ""
            self.resetScreen()
        }
    }
    
    //Ranging will detect relative distance to the beacon. It returns Far, Near or Immediate.
    func locationManager(_ manager: CLLocationManager, didRangeBeacons beacons: [CLBeacon], in region: CLBeaconRegion) {
        print("Found \(beacons.count) beacon")
        if beacons.count > 0 {
            print("Beacon \(beacons[0])")
            let tempName = String(format: "%d",beacons[0].minor.intValue)
            let tempArray = beaconArray.filter{$0["minor"] == tempName}
            self.beaconMajor = tempArray[0]["major"]!
            self.beaconMinor = tempArray[0]["minor"]!
            updateDistance(beacons[0].proximity)
        }
    }
    
    //Determine action to take when you detect a beacon based on the ranged distance
    func updateDistance(_ distance: CLProximity) {
        UIView.animate(withDuration: 0.8) {
            switch distance {
            case .unknown:
                break
            case .far:
                break
            case .near:
                break
            case .immediate:
                if self.beaconMajor == "1000" {
                    if self.beaconMinor != self.lastBuildingBeaconMinor {
                        self.updateView()
                    }
                    self.lastBuildingBeaconMinor = self.beaconMinor
                } else if self.beaconMajor == "2000" {
                    if self.beaconMinor != self.lastPopupBeaconMinor {
                        self.sendNotification(major: self.beaconMajor)
                    }
                    self.lastPopupBeaconMinor = self.beaconMinor
                } else if self.beaconMajor == "3000" {
                    if self.beaconMinor != self.lastExhibitBeaconMinor {
                        self.updateView()
                    }
                    self.lastExhibitBeaconMinor = self.beaconMinor
                }
            }
        }
    }
    
    func resetScreen() {
        let homeURL = self.baseURL + "index.html"
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
        print("Image: \(imageExists)")
        if (imageExists) {
            let task = URLSession.shared.dataTask(with: imageCloudURL!, completionHandler: { data, response, error in
                
                let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let fileURL = documentsURL.appendingPathComponent("\(self.beaconMinor).png")
                if ((error) == nil) {
                    do {
                        try UIImagePNGRepresentation(UIImage(data: (data)!)!)?.write(to: fileURL)
                    } catch {print ("Image error")
                    }
                }
                
                DispatchQueue.main.async {
                    self.assetImageURL = fileURL
                }
            })
            task.resume()
        } else {
            self.assetImageURL = Bundle.main.url(forResource: "wolves", withExtension: "jpg")
            print("No image: \(String(describing: self.assetImageURL))")
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
    
    //Compose the notification sent for a ranged beacon
    func sendNotification(major: String) {
        self.getGaeCloudContent({() in
            let content = UNMutableNotificationContent()
            content.title = "Speakin Beacon Demo"
            content.subtitle = "Proximity Notificaion"
            content.body = self.assetText
            content.sound = UNNotificationSound.default()
            content.categoryIdentifier = ""
            
            do {
                print("\(String(describing: self.assetImageURL))")
                let url = self.assetImageURL
                let attachment = try UNNotificationAttachment(identifier: "logo", url: url!, options: nil)
                content.attachments = [attachment]
                
                if major == "2000" {
                    //Add the action buttons in the notification
                    let appDelegate = UIApplication.shared.delegate as! AppDelegate
                    //appDelegate.notificationActionURL = self.baseURL + self.beaconUUID + "/" + self.beaconMajor + "/" + self.beaconMinor + "/index.html"
                    appDelegate.notificationActionURL = "https://www.ncsu.edu"
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
    
    //Compose the notification sent for a region monitored beacon
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
    
    //Update the UI with the new content loaded from GAE based on which becaon is detected
    func updateView() {
        self.getGaeCloudContent({() in
            var request = URLRequest(url: self.payloadURL!, cachePolicy:NSURLRequest.CachePolicy.reloadIgnoringLocalAndRemoteCacheData)
            request.setValue("text/html; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            self.messageView.loadRequest(request)
        })
    }
    
    
    //MARK: WebView Delegate
    //This function detects when a user taps a link in the UI web view.  If it is anything other than a GAE link, the new page open in SafariViewController.
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
    
    //If the device fails to load a web page, then load hte defaul Into page included in the app bundle.
    func webView(_ webView: UIWebView, didFailLoadWithError error: Error) {
        print("Webview error: \(error)")
        self.messageView.loadRequest(URLRequest(url: URL(fileURLWithPath: Bundle.main.path(forResource: "intro", ofType: "html")!)))
    }
    
    
    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        controller.dismiss(animated: true, completion: nil)
    }
    
    func fileExistsAt(url : URL, completion: @escaping (Bool) -> Void) {
        let checkSession = Foundation.URLSession.shared
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 1.0 // Adjust to your needs
        
        let task = checkSession.dataTask(with: request as URLRequest, completionHandler: { (data, response, error) -> Void in
            if let httpResp: HTTPURLResponse = response as? HTTPURLResponse {
                completion(httpResp.statusCode == 200 || httpResp.statusCode == 302 || httpResp.statusCode == 304)
            }
        })
        
        task.resume()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}

