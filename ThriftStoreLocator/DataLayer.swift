//
//  DataLayer.swift
//  ThriftStoreLocator
//
//  Created by Gary Shirk on 2/28/17.
//  Copyright © 2017 Gary Shirk. All rights reserved.
//

import Foundation
import CoreData

typealias DataLayerBlock = (ErrorType)->Void

class DataLayer {
    
    lazy var persistentContainer: NSPersistentContainer = {
        
        let container = NSPersistentContainer(name: "ThriftStoreLocator")
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }
        return container
    }()
}

extension DataLayer {
    
    func deleteCoreDataObjectsExceptFavorites(deleteAllStoresExceptFavsUpdater: DataLayerBlock? = nil) {
        
        var errorType = ErrorType.none
        
        persistentContainer.performBackgroundTask( {context in
            
            // Delete all stores currently in core data unless store is a favorite
            let fetchRequest: NSFetchRequest<Store> = Store.fetchRequest()
            let predicate = NSPredicate(format: "%K == %@", "isFavorite", NSNumber(value: false))
            fetchRequest.predicate = predicate
            
            let initialCount = try? context.count(for: fetchRequest)
            
            if let result = try? context.fetch(fetchRequest) {
                for object in result {
                    context.delete(object)
                }
            } else {
                errorType = ErrorType.coreDataSave(DebugErrorMessage.coreDataFetch)
            }
            
            do {
                try context.save()
        
            } catch let error as NSError  {
                errorType = ErrorType.coreDataSave(error.localizedDescription)
            }
            
            let finalCount = try? context.count(for: fetchRequest)
            
            print("Deleting all existing Stores except favorites: InitialCount: \(String(describing: initialCount)) --- FinalCount: \(String(describing: finalCount))")
            
            DispatchQueue.main.sync {
                deleteAllStoresExceptFavsUpdater?(errorType)
            }
        })
    }
    
    func updateFavorite(isFavOn: Bool, forStoreEntity store: Store, saveInBackgroundSuccess: DataLayerBlock? = nil) {
        
        var errorType = ErrorType.none
        
        persistentContainer.performBackgroundTask( {context in
        
            let fetchRequest: NSFetchRequest<Store> = Store.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "storeId == %@", store.storeId!)
        
            var storeEntity: Store?
            
            do {
                
                let storeEntities = try context.fetch(fetchRequest)
                storeEntity = storeEntities.first
                if isFavOn == true {
                    storeEntity?.isFavorite = 1
                } else {
                    storeEntity?.isFavorite = 0
                }

            } catch let error as NSError {
                errorType = ErrorType.coreDataFetch(error.localizedDescription)
            }
            
            do {
                
                try storeEntity?.managedObjectContext?.save()
                
            } catch let error as NSError {
                errorType = ErrorType.coreDataSave(error.localizedDescription)
            }
            
            DispatchQueue.main.sync {
                saveInBackgroundSuccess?(errorType)
            }
        })
    }
    
    func saveInBackground(stores: [[String:Any]], withDeleteOld deleteOld: Bool, isFavs: Bool, saveInBackgroundSuccess: DataLayerBlock? = nil) {
        
        var errorType = ErrorType.none
        
        // On background thread
        persistentContainer.performBackgroundTask( {context in
            
            let fetchRequest: NSFetchRequest<Store> = Store.fetchRequest()
            
            var uniqueStores = [[String:Any]]()
            
            if deleteOld {
                
                // Delete all stores currently in core data before loading new stores
                
                uniqueStores = stores
                
                let deleteRequst = NSBatchDeleteRequest(fetchRequest: fetchRequest as! NSFetchRequest<NSFetchRequestResult>)
                
                do {
                    let initialCount = try? context.count(for: fetchRequest)
                    try context.persistentStoreCoordinator?.execute(deleteRequst, with: context)
                    let finalCount = try? context.count(for: fetchRequest)
                    
                    print("Deleting existing Stores: InitialCount: \(String(describing: initialCount)) --- FinalCount: \(String(describing: finalCount))")
                    
                } catch let error as NSError {
                    errorType = ErrorType.coreDataDelete(error.localizedDescription)
                }
                
            } else {
                
                // Do not delete stores currently in core data, but before saving new ones, eliminate duplicates
                
                if let entityStores = try? context.fetch(fetchRequest) {
                    
                    for storeDict in stores {
                        
                        var duplicate = false
                        
                        for entityStore in entityStores {
                            
                            if ((storeDict["storeId"] as! NSString).integerValue as NSNumber) == entityStore.storeId {
                                
                                duplicate = true
                                
                                break
                            }
                        }
                        
                        if !duplicate {
                            uniqueStores.append(storeDict)
                        }
                    }
                }
            }
            
            // Save stores downloaded from server to Core Data
            do {
                
                // Note: Below commented-out code shows how to manage core data relations between Store and Favorite entities
                // Current, this relationship is not being used
                // let favEntity = NSEntityDescription.entity(forEntityName: "Favorite", in: context)
                // let favorite = Favorite(entity: favEntity!, insertInto: context)
                // favorite.username = "myuser"
                
            
                for storeDict:[String:Any] in uniqueStores {
                
                    let entity = NSEntityDescription.entity(forEntityName: "Store", in: context)
                
                    if let entity = entity {
                        
                        let store = Store(entity: entity, insertInto: context)
                        
                        store.name = storeDict["name"] as? String
                        store.storeId = (storeDict["storeId"] as! NSString).integerValue as NSNumber?
                        store.categoryMain = storeDict["categoryMain"] as? String
                        store.categorySub = storeDict["categorySub"] as? String
                        store.address = storeDict["address"] as? String
                        store.city = storeDict["city"] as? String
                        store.state = storeDict["state"] as? String
                        store.zip = storeDict["zip"] as? String
                        store.phone = storeDict["phone"] as? String
                        store.email = storeDict["email"] as? String
                        store.website = storeDict["website"] as? String
                        store.locLat = (storeDict["locLat"] as? NSString)?.doubleValue as NSNumber?
                        store.locLong = (storeDict["locLong"] as? NSString)?.doubleValue as NSNumber?
                        store.county = storeDict["county"] as? String
                        
                        if isFavs == true {
                            store.isFavorite = 1
                        } else {
                            store.isFavorite = 0
                        }
                        
                        //favorite.addToStores(store)
                        
                        try store.managedObjectContext?.save()
                    }
                    //try favorite.managedObjectContext?.save()
                }
            } catch let error as NSError {
                errorType = ErrorType.coreDataSave(error.localizedDescription)
            }
            
            DispatchQueue.main.sync {
                saveInBackgroundSuccess?(errorType)
            }
        })
    }
    
    func getAllStoresOnMainThread() -> [Store] {
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Store")

        let stores = try! persistentContainer.viewContext.fetch(fetchRequest)
       
        return stores as! [Store]
    }
    
    func getLocationFilteredStoresOnMainThread(forPredicate predicate: NSPredicate) -> [Store] {
       
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Store")
        fetchRequest.predicate = predicate
        
        let stores = try! persistentContainer.viewContext.fetch(fetchRequest)
        
        return stores as! [Store]
    }
    
    func getFavoriteStoresOnMainThread() -> [Store] {
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Store")
        let predicate = NSPredicate(format: "%K == %@", "isFavorite", NSNumber(value: true))
        fetchRequest.predicate = predicate
        
        let stores = try! persistentContainer.viewContext.fetch(fetchRequest)
        //stores.forEach { print(($0 as AnyObject).name as! String) }
        
        return stores as! [Store]
    }
}
