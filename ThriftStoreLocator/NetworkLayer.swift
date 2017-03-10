//
//  NetworkLayer.swift
//  ThriftStoreLocator
//
//  Created by Gary Shirk on 2/28/17.
//  Copyright © 2017 Gary Shirk. All rights reserved.
//

import Foundation
import Alamofire
import SwiftyJSON

// TODO - constants should use pattern for constants (struct or enum)
private let baseURL = "http://127.0.0.1:3000/stores"  //"http://localhost:3000/stores" //"https://jsonplaceholder.typicode.com/todos"

var useDebug = false

class NetworkLayer {
    
    // TODO - Probably should change AnyObject to Any
    var storesArrayOfDicts = [[String:Any]]() // Array of Dictionaries
    
    func loadStoresFromServer(modelManagerUpdater: @escaping ([[String:Any]]) -> Void) {
        
        
        // DEBUG
        if useDebug {
            loadStoresLocally()
            modelManagerUpdater(storesArrayOfDicts)
            return
        }
        
        
        Alamofire.request(baseURL, method: .get).validate()
            
            // TODO - Using [weak self] here; is it required?
            .responseJSON(completionHandler: { [weak self] response in
                
                guard let strongSelf = self else { return }
                
                switch response.result {
                
                case .success(let value):
                    
                    let json = JSON(value)
                    
                    //print("JSON: \(json)")
                    
                    if let jsonArray = json.array {
                        
                        for item in jsonArray {
                            if let jsonDict = item.dictionary {
                                
                                var itemDict = [String:String]()
                                
                                itemDict["name"] = jsonDict["bizName"]?.stringValue
                                itemDict["storeId"] = jsonDict["bizID"]?.stringValue
                                itemDict["categoryMain"] = jsonDict["bizCat"]?.stringValue
                                itemDict["categorySub"] = jsonDict["bizCatSub"]?.stringValue
                                itemDict["address"] = jsonDict["bizAddr"]?.stringValue
                                itemDict["city"] = jsonDict["bizCity"]?.stringValue
                                itemDict["state"] = jsonDict["bizState"]?.stringValue
                                itemDict["zip"] = jsonDict["bizZip"]?.stringValue
                                itemDict["phone"] = jsonDict["bizPhone"]?.stringValue
                                itemDict["email"] = jsonDict["bizEmail"]?.stringValue
                                itemDict["website"] = jsonDict["bizURL"]?.stringValue
                                itemDict["locLat"] = jsonDict["locLat"]?.stringValue
                                itemDict["locLong"] = jsonDict["locLong"]?.stringValue
                                itemDict["county"] = jsonDict["locCounty"]?.stringValue
                                
                                strongSelf.storesArrayOfDicts.append(itemDict as [String : Any])
                            }
                        }
                    }
                    
                    print("Test stores loaded from REST server")
                    modelManagerUpdater(strongSelf.storesArrayOfDicts)
                
                case .failure(let error):
                    // TODO - Proper error handling
                    print(error)
                }
            })
    }
    
    func loadStoresLocally() {
        
        let storeDict  = [
            "name": "Goodwill",
            "storeId": "1",
            "address": "1430 E Algonquin Rd",
            "city": "Algonquin",
            "state": "IL",
            "zip": "60102",
            "phone": "630-772-1345",
            "email": "",
            "website": "",
            "locLat": "42.2",
            "locLong": "-88.3",
        ] as [String : Any]
        
        storesArrayOfDicts.append(storeDict)
    }

}
