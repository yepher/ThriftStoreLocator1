//
//  StoresViewModel.swift
//  ThriftStoreLocator
//
//  Created by Gary Shirk on 2/28/17.
//  Copyright © 2017 Gary Shirk. All rights reserved.
//

import Foundation
import CoreLocation
import MapKit

protocol StoresViewModelDelegate: class {
    
    func handleStoresUpdated(forLocation location:CLLocationCoordinate2D)
    
    func handleFavoritesLoaded()
}

class StoresViewModel {
    
    private var modelManager: ModelManager
    
    weak var delegate: StoresViewModelDelegate?
    
    var stores: [Store] = []
    
    var county: String = ""
    
    var state: String = ""
    
    var query: String = ""
    
    var storeFilterPredicate: NSPredicate?
    
    var storeFilterDict = [String: NSPredicate]()
    
    var mapLocation: CLLocationCoordinate2D?
    
    lazy var geocoder = CLGeocoder()
    
    init(delegate: StoresViewModelDelegate?) {
        self.delegate = delegate
        self.modelManager = ModelManager.sharedInstance
    }
    
    func postFavorite(forStore store: Store, user: String) {
        
        modelManager.postFavoriteToServer(store: store, forUser: user, modelManagerPostFavUpdater: {
        
            print("modelManagerPostFavUpdater ran - setting of Fav to db and updating store core data object complete")
        
        })
    }
    
    func removeFavorite(forStore store: Store, user: String) {
        
        modelManager.removeFavoriteFromServer(store: store, forUser: user, modelManagerPostFavUpdater: {
            
            print("modelManagerPostFavUpdater ran - removal of Fav from db and updating store core data object complete")
            
        })
    }
    
    func loadFavorites(forUser user: String) {
        
        modelManager.loadFavoritesFromServer(forUser: user, modelManagerLoadFavoritesUpdater: { [weak self] storeEntities -> Void in
        
            guard let strongSelf = self else {
                return
            }
            
            strongSelf.delegate?.handleFavoritesLoaded()
        })
    }
    
    func loadStores(forLocation location: CLLocationCoordinate2D, withRefresh isRefresh: Bool, withRadiusInMiles radius: Double) {
        setStoreFilters(forLocation: location, withRadiusInMiles: radius, andZip: "")
        setCounty(forLocation: location, deleteOld: isRefresh)
    }
    
    func loadStores(forSearchStr searchStr: String) {
        setLocationInfo(forAddressStr: searchStr)
    }
    
    func doLoadStores(deleteOld: Bool) {
        
        // Check if we already loaded stores for the current county previously
        if let _ = storeFilterDict[self.county] {
            
            let stores = modelManager.getAllStoresOnMainThread()
            filterStoresAndInformMainController(stores: stores)
            
        } else {
        
            modelManager.loadStoresFromServer(forQuery: query, withDeleteOld: deleteOld, modelManagerStoresUpdater: { [weak self] storeEntities -> Void in
                
                guard let strongSelf = self else {
                    return
                }
                
                strongSelf.storeFilterDict[strongSelf.county] = strongSelf.storeFilterPredicate
                strongSelf.filterStoresAndInformMainController(stores: storeEntities)
            })
        }
    }
    
    func filterStoresAndInformMainController(stores: [Store]) {
        let filteredStores = (stores as NSArray).filtered(using: self.storeFilterPredicate!)
        self.stores = filteredStores as! [Store]
        self.delegate?.handleStoresUpdated(forLocation: self.mapLocation!)
    }
    
    func prepareForZoomToMyLocation(location:CLLocationCoordinate2D) {
        stores = modelManager.getAllStoresOnMainThread()
        setStoreFilters(forLocation: location, withRadiusInMiles: 10, andZip: "")
        setCounty(forLocation: location, deleteOld: true)
    }
    
    // Get the approximate area (expects radius to be in units of miles)
    func setStoreFilters(forLocation location: CLLocationCoordinate2D, withRadiusInMiles radius:Double, andZip zip:String) {
        
        // TODO - Not ready for this yet, but once you start notifying user about geofence entries, will need to use CLCircularRegion
        // let region = CLCircularRegion.init(center: location, radius: radius, identifier: "region")
        
        // TODO - Place coord keys in constant class
        self.mapLocation = location
        
        if zip.isEmpty {
            
            // Approximate a region based on location and radius, does not account for curvature of earth but ok for short distances
            let locLat = location.latitude
            let locLong = location.longitude
            let degreesLatDelta = milesToLatDegrees(for: radius)
            let degreesLongDelta = milesToLongDegrees(for: radius, atLatitude: locLat)
            
            let eastLong = locLong + degreesLongDelta
            let westLong = locLong - degreesLongDelta
            let northLat = locLat + degreesLatDelta
            let southLat = locLat - degreesLatDelta
            
            let predicateNorthLat = NSPredicate(format: "%K < %@", "locLat", NSNumber(value: northLat))
            let predicateSouthLat = NSPredicate(format: "%K > %@", "locLat", NSNumber(value: southLat))
            let predicateEastLong = NSPredicate(format: "%K < %@", "locLong", NSNumber(value: eastLong))
            let predicateWestLong = NSPredicate(format: "%K > %@", "locLong", NSNumber(value: westLong))
            storeFilterPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicateNorthLat, predicateSouthLat, predicateEastLong, predicateWestLong])
            
            //print("RegionLong: westLong: \(westLong), centerLong: \(locLong), eastLong: \(eastLong)")
            //print("RegionLat : northLat: \(northLat), centerLat: \(locLat), southLat: \(southLat)")
            
        } else {
            
             storeFilterPredicate = NSPredicate(format: "%K == %@", "zip", zip)
        }
    }
    
    func isZipCode(forSearchStr searchStr:String) -> Bool {
        let regex = "^([^a-zA-Z][0-9]{4})$"
        if let _ = searchStr.range(of: regex, options: .regularExpression) {
            return true
        } else {
            return false
        }
    }
    
    func setCounty(forLocation location: CLLocationCoordinate2D, deleteOld: Bool) {
        
        let locationCoords: CLLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        
        geocoder.reverseGeocodeLocation(locationCoords) { (placemarks, error) in
            
            if error != nil {
                print("Reverse geocoder failed with error" + (error?.localizedDescription)!)
                return
            }
            
            if let placemarks = placemarks, let placemark = placemarks.first {
                
                if let cty = placemark.subAdministrativeArea?.lowercased().replacingOccurrences(of: " ", with: "+") {
                    self.county = cty
                    if let state = placemark.administrativeArea {
                        self.state = state
                        self.query = self.state + "/" + self.county
                        
                        self.doLoadStores(deleteOld: deleteOld)
                    } else {
                        print("Problem getting state")
                    }
                }
            
            } else {
                print("Problem getting county")
            }
        }
    }
    
    func setLocationInfo(forAddressStr address: String) {
        
        geocoder.geocodeAddressString(address) { (placemarks, error) in
            
            if error != nil {
                print("Geocoder failed with error" + (error?.localizedDescription)!)
                return
            }
            
            if let placemarks = placemarks, let placemark = placemarks.first {
                
                // If user's search did not yield a county, eg user searched for a state, then do not allow the search
                if let cty = placemark.subAdministrativeArea?.lowercased().replacingOccurrences(of: " ", with: "+") {
                    self.county = cty
                    self.state = placemark.administrativeArea!
                    self.query = self.state + "/" + self.county
                    self.mapLocation = placemark.location?.coordinate
                    
                    var zip = ""
                    let isZip = self.isZipCode(forSearchStr: address)
                    if isZip == true {
                        zip = address
                    }
                    
                    self.setStoreFilters(forLocation: self.mapLocation!, withRadiusInMiles: 10, andZip: zip)
                    
                    self.doLoadStores(deleteOld: false)
                }
                
            } else {
                print("Problem getting county")
            }
        }
    }
}

extension StoresViewModel {
    
    func milesToLatDegrees(for miles:Double) -> Double {
        // TODO - Add to constants class
        return miles / 69.0
    }
    
    func milesToLongDegrees(for miles:Double, atLatitude lat:Double) -> Double {
        
        // Approximations for long degree deltas based on lat found at www.csgnetwork.com/degreelenllavcalc.html
        
        let milesPerDeg:Double
        
        switch lat {
        
        case 0..<25.0:
            milesPerDeg = 62.7 // lat: 25.0
            break
            
        case 25.0..<30.0:
            milesPerDeg = 61.4 // lat: 27.5
            break
            
        case 30.0..<35.0:
            milesPerDeg = 58.4 // lat: 32.5
            break
            
        case 35.0..<40.0:
            milesPerDeg = 55.0 // lat: 37.5
            break
            
        case 40.0..<45.0:
            milesPerDeg = 51.1 // lat: 42.5
            break
            
        case 45.0..<60.0:
            milesPerDeg = 47.3 // lat: 47.0
            break
            
        default:
            milesPerDeg = 55.0 // lat:
            break
        }
        
        return miles / milesPerDeg
    }
}
