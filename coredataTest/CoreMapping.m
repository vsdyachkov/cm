//
//  CoreMapping.m
//  CoreMapping
//
//  Created by Dyachkov Victor on 26.08.14.
//  Copyright (c) 2014 Dyachkov Victor. All rights reserved.
//

#import "CoreMapping.h"



@implementation CoreMapping


#pragma mark - Core Data stack

+ (NSManagedObjectModel *)managedObjectModel
{
    if (managedObjectModel != nil)
        return managedObjectModel;
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:SQLFileName withExtension:@"momd"];
    managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    return managedObjectModel;
}

+ (NSPersistentStoreCoordinator *)persistentStoreCoordinator
{
    if (persistentStoreCoordinator != nil)
        return persistentStoreCoordinator;
    NSString* pathComponent = [NSString stringWithFormat:@"%@.sqlite", SQLFileName];
    NSURL *storeURL = [[self applicationDocumentsDirectory] URLByAppendingPathComponent:pathComponent];
    NSError *error = nil;
    persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];
    if (![persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error]) {
        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
        abort();
    }
    return persistentStoreCoordinator;
}

+ (NSManagedObjectContext *)managedObjectContext
{
    if (managedObjectContext != nil)
        return managedObjectContext;
    NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
    if (coordinator != nil) {
        managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        [managedObjectContext setPersistentStoreCoordinator:coordinator];
    }
    return managedObjectContext;
}

+ (NSManagedObjectContext *)childManagedObjectContext
{
    if (childManagedObjectContext != nil)
        return childManagedObjectContext;
    NSManagedObjectContext *childManagedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    [childManagedObjectContext setParentContext:[self managedObjectContext]];
    return childManagedObjectContext;
}

+ (void)saveContext
{
    if ([NSThread isMainThread]) {
        [self saveMainContext];
    } else {
        [self saveChildContext];
        [[self managedObjectContext] performBlock:^{
            [self saveMainContext];
        }];
    }
}

+ (NSError*) saveMainContext
{
    NSError* error;
    [[self managedObjectContext] save:&error];
    if (error) NSLog(@"Can't save context, error: %@", error.localizedDescription);
    return error;
}

+ (NSError*) saveChildContext
{
    NSError* error;
    [[self childManagedObjectContext] save:&error];
    if (error) NSLog(@"Can't save child context, error: %@", error.localizedDescription);
    return error;
}

+ (NSManagedObjectContext*) contextForCurrentThread
{
    return ([NSThread isMainThread]) ? [self managedObjectContext] : [self childManagedObjectContext];
}



#pragma mark - Application's Documents directory


+ (NSURL *)applicationDocumentsDirectory
{
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}



#pragma mark - Helper methods

+ (BOOL) isArray: (id) object
{
    return (object && [object isKindOfClass:[NSArray class]]) ? YES : NO;
}

+ (BOOL) isDictionary: (id) object
{
    return (object && [object isKindOfClass:[NSDictionary class]]) ? YES : NO;
}

+ (NSNumber*) relationshipIdFrom: (NSRelationshipDescription*) relation to: (NSRelationshipDescription*) inverse
{
    if (!relation.isToMany && !inverse.isToMany) return @0;
    if (relation.isToMany && !inverse.isToMany)  return @1;
    if (!relation.isToMany && inverse.isToMany)  return @2;
    if (relation.isToMany && inverse.isToMany)   return @3;
    return nil;
}

+ (NSString*) relationshipNameWithId: (NSNumber*) number
{
    switch (number.intValue) {
        case 0: return @"OneToOne"; break;
        case 1: return @"OneToMany"; break;
        case 2: return @"ManyToOne"; break;
        case 3: return @"ManyToMany"; break;
        default: return nil; break;
    }
}



#pragma mark - Core Mapping stack


+ (void) status
{
    [self fullPrint:YES];
}

+ (void) shortStatus
{
    [self fullPrint:NO];
}


+ (void) fullPrint: (BOOL) full
{
    NSMutableString* report = @"Current Core Data status:\n".mutableCopy;
    for (NSEntityDescription* entityDescription in [self.managedObjectModel entities])
    {
        
        NSFetchRequest* request = [[NSFetchRequest alloc]initWithEntityName:entityDescription.name];
        NSArray* arr = [[CoreMapping managedObjectContext] executeFetchRequest:request error:nil];
        if (full)
            [report appendString:@"\n"];
        [report appendFormat:@"Entity: %@ {%d rows} \n", entityDescription.name, arr.count];
        if (full) {
            [report appendString:@"\n"];
        } else {
            continue;
        }
        [arr enumerateObjectsUsingBlock:^(NSManagedObject* obj, NSUInteger idx, BOOL *stop) {
            [report appendFormat:@"- %@\n\n", obj];
        }];
        if (arr.count < 1)
            [report appendString:@"- <Empty>"];
    }
    NSLog(@"%@",report);
}

+ (void)clearDatabase
{
    NSArray *entities = [[self.managedObjectModel entities] valueForKey:@"name"];
    
    for (NSString* entityName in entities)
    {
        NSFetchRequest *fetchRequest = [NSFetchRequest new];
        NSEntityDescription *entity = [NSEntityDescription entityForName:entityName inManagedObjectContext:self.managedObjectContext];
        [fetchRequest setEntity:entity];
        NSError *error;
        NSArray *items = [self.managedObjectContext executeFetchRequest:fetchRequest error:&error];
        for (NSManagedObject *managedObject in items) {
            [self.managedObjectContext deleteObject:managedObject];
        }
        if (![self.managedObjectContext save:&error]) {
            NSLog(@"Error: %@",error.localizedDescription);
        }
    }
}

+ (void) mapValue:(id) value withJsonKey: (NSString*) key andType: (NSAttributeType) type andManagedObject: (NSManagedObject*) obj
{
    if (!value || !key || !type || !obj)
        return;
    
    id convertedValue;
    NSString* strValue = [NSString stringWithFormat:@"%@",value];
    switch (type) {
        case NSUndefinedAttributeType: convertedValue =  nil; break;
        case NSInteger16AttributeType: convertedValue =  [NSNumber numberWithInt:[strValue integerValue]]; break;
        case NSInteger32AttributeType: convertedValue =  [NSNumber numberWithInt:[strValue integerValue]]; break;
        case NSInteger64AttributeType: convertedValue =  [NSNumber numberWithInt:[strValue integerValue]]; break;
        case NSDecimalAttributeType: convertedValue =    [NSNumber numberWithInt:[strValue doubleValue]]; break;
        case NSDoubleAttributeType: convertedValue =     [NSNumber numberWithInt:[strValue doubleValue]]; break;
        case NSFloatAttributeType: convertedValue =      [NSNumber numberWithInt:[strValue floatValue]]; break;
        case NSStringAttributeType: convertedValue =     strValue; break;
        case NSBooleanAttributeType: convertedValue =    [NSNumber numberWithInt:[strValue boolValue]]; break;
        case NSDateAttributeType: convertedValue =       nil; break;
        case NSBinaryDataAttributeType: convertedValue = [strValue dataUsingEncoding:NSUTF8StringEncoding]; break;
        /*
        case 1800:   return @"NSTransformableAttributeType";
        case 2000:   return @"NSObjectIDAttributeType";
        */
        default: [NSException raise:@"Invalid attribute type" format:@"This type is not supported in database"]; break;
    }

    [obj setValue:convertedValue forKey:key];
}

+ (NSManagedObject*) findOrCreateObjectInEntity: (NSEntityDescription*) entity withId: (NSNumber*) idNumber
{
    if (!entity || !idNumber)
        return nil;
    
    NSFetchRequest* req = [[NSFetchRequest alloc]initWithEntityName:entity.name];
    NSString* idString = [entity idKeyString];
    NSPredicate* myPred = [NSPredicate predicateWithFormat:@"%K == %@", idString, idNumber];
    [req setPredicate:myPred];
    
    NSArray* arr = [self.managedObjectContext executeFetchRequest:req error:nil];
    if (arr.count > 0) {
        return arr[0];
    } else {
        return [NSEntityDescription insertNewObjectForEntityForName:entity.name inManagedObjectContext:self.managedObjectContext];
    }
}

+ (NSManagedObject*) mapSingleRowInEntity: (NSEntityDescription*) desc andJsonDict: (NSDictionary*) json
{
    if (!desc || !json)
        return nil;
    
    NSNumber* idFromJson = @([json[@"id"] integerValue]);
    NSManagedObject* obj = [self findOrCreateObjectInEntity:desc withId:idFromJson];
    NSDictionary* attributes = [desc attributesByName];
    [[attributes allValues] enumerateObjectsUsingBlock:^(NSAttributeDescription* attr, NSUInteger idx, BOOL *stop) {
        NSString* mappingAttrName = [attr mappingName];
        id valueFromJson = json [mappingAttrName];
        [self mapValue:valueFromJson withJsonKey:attr.name andType:attr.attributeType andManagedObject:obj];
    }];
    

    // perform Relationships: ManyToOne & OneToOne
    
    for (NSString* name in desc.relationshipsByName) {
        
        NSRelationshipDescription* relationFromChild = desc.relationshipsByName[name];
        NSRelationshipDescription* inverseFromParent = relationFromChild.inverseRelationship;
        
        // This (many) Childs to -> (one) Parent
        
        //if (!relationFromChild.isToMany) {
            
            NSEntityDescription* destinationEntity = relationFromChild.destinationEntity;
            NSString* relationMappedName = [relationFromChild mappingName];
            NSNumber* idObjectFormJson = json[relationMappedName];
            
            NSManagedObject* toObject = [self findOrCreateObjectInEntity:destinationEntity withId:idObjectFormJson];
            NSString* selectorName = [NSString stringWithFormat:@"add%@Object:", inverseFromParent.name.capitalizedString];
            [toObject performSelectorIfResponseFromString:selectorName withObject:obj];
            
        //}
    }
    
    //
    
    return obj;
}

+ (void) mapAllRowsInEntity: (NSEntityDescription*) desc andWithJsonArray: (NSArray*) jsonArray
{
    if (!desc || !jsonArray)
        return;
    
    [jsonArray enumerateObjectsUsingBlock:^(NSDictionary* singleDict, NSUInteger idx, BOOL *stop) {
        NSManagedObject* obj = [self mapSingleRowInEntity:desc andJsonDict:singleDict];
        [obj performSelectorIfResponseFromString:@"customizeWithJson:" withObject:singleDict];
    }];
}

+ (void) removeRowsInEntity: (NSEntityDescription*) desc withNumberArray: (NSArray*) removeArray
{
    if (!desc || !removeArray)
        return;
    
    [removeArray enumerateObjectsUsingBlock:^(NSNumber* removeId, NSUInteger idx, BOOL *stop) {
        NSFetchRequest* req = [[NSFetchRequest alloc]initWithEntityName:desc.name];
        NSPredicate* myPred = [NSPredicate predicateWithFormat:@"%K == %@", [desc idKeyString], removeId];
        [req setPredicate:myPred];
        NSArray* arr = [[self managedObjectContext] executeFetchRequest:req error:nil];
        if (arr.count > 0) {
            [[self managedObjectContext] deleteObject:arr[0]];
        }
    }];
}

+ (void) mapAllEntityWithJson: (NSDictionary*) json
{
    if (!json)
        return;
    
    NSArray* entities = [self.managedObjectModel entities];
    [entities enumerateObjectsUsingBlock:^(NSEntityDescription* desc, NSUInteger idx, BOOL *stop) {
        NSString* mappingEntityName = [desc mappingName];
        NSArray* arrayWithName = json[mappingEntityName];
        [self mapAllRowsInEntity:desc andWithJsonArray:arrayWithName];
        [self saveContext];
    }];
}

+ (void) syncWithJson: (NSDictionary*) json
{
    if (!json)
        return;
    
    NSArray* entities = [self.managedObjectModel entities];
    [entities enumerateObjectsUsingBlock:^(NSEntityDescription* desc, NSUInteger idx, BOOL *stop) {
        
        NSString* mappingEntityName = [desc mappingName];

        if ([self isArray:json[mappingEntityName][@"add"]]) {
            NSArray* addArray = json[mappingEntityName][@"add"];
            if (addArray.count > 0) {
                [self mapAllRowsInEntity:desc andWithJsonArray:addArray];
            }
        }
        
        if ([self isArray:json[mappingEntityName][@"remove"]]) {
            NSArray* removeArray = json[mappingEntityName][@"remove"];
            if (removeArray.count > 0) {
                [self removeRowsInEntity:desc withNumberArray:(NSArray*)removeArray];
            }
        }

    }];
    [self saveContext];
}

+ (void) saveInBackgroundWithBlock: (void(^)(NSManagedObjectContext *context))block completion:(void(^)(BOOL success, NSError *error)) completion
{
    NSManagedObjectContext *childManagedObjectContext = [self childManagedObjectContext];
    [childManagedObjectContext performBlock:^{
        if (block) {
            block(childManagedObjectContext);
            NSError* error1 = [self saveChildContext];
            [[self managedObjectContext] performBlock:^{
                NSError* error2 = [self saveMainContext];
                BOOL isSuccess = (!error1 && !error2);
                NSString* errorDesc = [NSString stringWithFormat:@"Errors: %@, %@", error1.localizedDescription, error2.localizedDescription];
                NSError* fatalError = [NSError errorWithDomain:errorDesc code:-1 userInfo:nil];
                if (completion) {
                    (isSuccess) ? completion(YES, nil) : completion(NO, fatalError);
                }
            }];
        }
    }];
}



@end
