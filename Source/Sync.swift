import UIKit
import CoreData
import NSString_HYPNetworking
import DATAStack
import DATAFilter
import NSManagedObject_HYPPropertyMapper
import NSDictionary_ANDYSafeValue

let CustomPrimaryKey = "hyper.isPrimaryKey"
let CustomRemoteKey = "hyper.remoteKey"
let DefaultLocalPrimaryKey = "remoteID"
let DefaultRemotePrimaryKey = "id"

private extension NSEntityDescription {

  func sync_localKey() -> String {
    var localKey: String?

    for (key, attributedDescription) in self.propertiesByName {
      if let userInfo: Dictionary = attributedDescription.userInfo,
        customPrimaryKey = userInfo[CustomPrimaryKey] as? String
        where customPrimaryKey == "YES" {
          localKey = key as? String
      }
    }

    if !(localKey != nil) {
      localKey = DefaultLocalPrimaryKey
    }

    return localKey!
  }

  func sync_remoteKey() -> String {
    var remoteKey: String?
    let localKey = sync_localKey()

    if localKey == remoteKey {
      remoteKey = DefaultRemotePrimaryKey
    } else {
      remoteKey = localKey.hyp_remoteString()
    }

    return remoteKey!
  }

}

public extension NSManagedObject {

  private func sync_copyInContext(context: NSManagedObjectContext) -> NSManagedObject? {
    let entity = NSEntityDescription.entityForName(self.entity.name!,
        inManagedObjectContext: context)

    let localKey = entity!.sync_localKey()
//    let remoteID = self.valueForKey(localKey)
// TODO: Implement this
    return nil
  }

  private func sync_relationships() -> [NSRelationshipDescription] {
    var relationships: [NSRelationshipDescription] = []

    for property in self.entity.properties {
      if property is NSRelationshipDescription {
        relationships.append(property as! NSRelationshipDescription)
      }
    }

    return relationships
  }

  func sync_processRelationshipsUsingDictionary(objectDictionary dictionary: [NSObject : AnyObject], andParent parent: NSManagedObject?, dataStack: DATAStack!) {
    let relationships = self.sync_relationships()

    for relationship: NSRelationshipDescription in relationships {
      if relationship.toMany {
        self.sync_processToManyRelationship(relationship,
          usingDictionary: dictionary,
          andParent: parent!,
          datastack: dataStack)
      } else if parent != nil && relationship.destinationEntity?.name == parent?.entity.name! {
        self.setValue(parent, forKey: relationship.name)
      } else {
        self.sync_processToOneRelationship(relationship, usingDictionary: dictionary)
      }
    }
  }

  private func sync_processToManyRelationship(relationship: NSRelationshipDescription, usingDictionary dictionary: [NSObject : AnyObject], andParent parent: NSManagedObject!, datastack: DATAStack) {

    var relationshipName: String
    if let userInfo: Dictionary = relationship.userInfo,
      relationshipKey = userInfo[CustomRemoteKey] as? String {
        relationshipName = relationshipKey
    } else {
      relationshipName = relationship.name
    }

    let childEntityName: String = relationship.destinationEntity!.name!
    let parentEntityName: String = parent.entity.name!
    let inverseEntityName: String = relationship.inverseRelationship!.name
    let inverseIsToMany: Bool = relationship.inverseRelationship!.toMany
    let hasValidManyToManyRelationship = (parent != nil && inverseIsToMany && parentEntityName == childEntityName)

    if let children = dictionary[relationshipName] as? [NSObject] {
      var childPredicate: NSPredicate
      let entity = NSEntityDescription.entityForName(childEntityName, inManagedObjectContext: self.managedObjectContext!)

      if inverseIsToMany {
//        if let destinationRemoteKey = entity?.sync_remoteKey() ,
//          childrenIDs: AnyObject? = children[destinationRemoteKey],
//          destinationLocalKey = entity?.sync_localKey() {
////            if childIDs.count == 1 {
////            }
//        }
      } else {
        // TODO: Implement this
      }

    }
  }

  func sync_processToOneRelationship(relationship: NSRelationshipDescription, usingDictionary dictionary: [NSObject : AnyObject]) {
    var relationshipName: String
    if let userInfo: Dictionary = relationship.userInfo,
      relationshipKey = userInfo[CustomRemoteKey] as? String {
        relationshipName = relationshipKey
    } else {
      relationshipName = relationship.name
    }

    let entityName = relationship.destinationEntity?.name
    let entity = NSEntityDescription.entityForName(entityName!, inManagedObjectContext: self.managedObjectContext!)
    if let filteredObjectDictionary = dictionary[relationshipName] as? [NSObject : AnyObject] {
      if let remoteKey = entity?.sync_remoteKey(),
        remoteID = dictionary[remoteKey] as? String{
          if let object = Sync.safeObjectInContext(self.managedObjectContext!, entityName: entityName!, remoteID: remoteID) {
            object.hyp_fillWithDictionary(filteredObjectDictionary)
            self.setValue(object, forKey: relationship.name)
          } else if let object = NSEntityDescription.insertNewObjectForEntityForName(entityName!, inManagedObjectContext: self.managedObjectContext!) as? NSManagedObject {
            object.hyp_fillWithDictionary(filteredObjectDictionary)
            self.setValue(object, forKey: relationship.name)
          }
      }
    }
  }

}

public class Sync {

  static func safeObjectInContext(context: NSManagedObjectContext, entityName: String, remoteID: String) -> NSManagedObject? {
    var error: NSError?
    let entity = NSEntityDescription .entityForName(entityName, inManagedObjectContext: context)
    let request = NSFetchRequest(entityName: entityName)
    let localKey = entity?.sync_localKey()

    request.predicate = NSPredicate(format: "%K = %@", localKey!, remoteID)

    let objects = context.executeFetchRequest(request, error: &error)

    if (error != nil) {
      println("parentError: \(error)")
    }

    if let firstObject: AnyObject = objects?.first,
      managedObject: NSManagedObject = firstObject as? NSManagedObject {
      return managedObject
    } else {
      return nil
    }
  }

  public func process(#changes: [AnyObject],
    inEntityNamed entityName: String,
    dataStack: DATAStack,
    completion: (error: NSError) -> Void) {
      [self.process(changes: changes,
        inEntityNamed: entityName,
        predicate: nil,
        dataStack: dataStack,
        completion: completion)]
  }

  public func process(#changes: [AnyObject],
    inEntityNamed entityName: String,
    predicate: NSPredicate?,
    dataStack: DATAStack,
    completion: (error: NSError) -> Void) {
      dataStack.performInNewBackgroundContext {
        (backgroundContext: NSManagedObjectContext!) in
        [self.process(changes: changes,
          inEntityNamed: entityName,
          predicate: nil,
          parent:nil,
          inContext: backgroundContext,
          dataStack: dataStack,
          completion: completion)]
      }
  }

  public func process(#changes: [AnyObject],
    inEntityNamed entityName: String,
    predicate: NSPredicate?,
    parent: NSManagedObject,
    dataStack: DATAStack,
    completion: (error: NSError) -> Void) {
      dataStack.performInNewBackgroundContext {
        (backgroundContext: NSManagedObjectContext!) in

        let safeParent = parent.sync_copyInContext(backgroundContext)
        let predicate = NSPredicate(format: "%K = %@", parent.entity.name!, safeParent!)

        self.process(changes: changes,
          inEntityNamed: entityName,
          predicate: predicate,
          parent:parent,
          inContext: backgroundContext,
          dataStack: dataStack,
          completion: completion)
      }
  }

  public func process(#changes: [AnyObject],
    inEntityNamed entityName: String,
    predicate: NSPredicate?,
    parent: NSManagedObject?,
    inContext context: NSManagedObjectContext,
    dataStack: DATAStack,
    completion: (error: NSError) -> Void) {
      let entity = NSEntityDescription.entityForName(entityName, inManagedObjectContext: context)

      DATAFilter.changes(changes,
        inEntityNamed: entityName,
        localKey: entity!.sync_localKey(),
        remoteKey: entity!.sync_remoteKey(),
        context: context,
        predicate: predicate,
        inserted: {
          (JSON: [NSObject : AnyObject]!) in
          let created: AnyObject = NSEntityDescription.insertNewObjectForEntityForName(entityName, inManagedObjectContext: context)
          created.hyp_fillWithDictionary(JSON)
          created.sync_processRelationshipsUsingDictionary(objectDictionary: JSON, andParent: parent, dataStack: dataStack)
        }, updated: {
          (JSON: [NSObject : AnyObject]!, updatedObject: NSManagedObject!) in
          updatedObject.hyp_fillWithDictionary(JSON)
          updatedObject.sync_processRelationshipsUsingDictionary(objectDictionary: JSON, andParent: parent, dataStack: dataStack)
      })

      var error: NSError?
      context.save(&error)

      if error != nil {
        println("Sync (error while saving \(entityName): \(error?.description)")
      }

      dataStack.persistWithCompletion {

      }
  }

}