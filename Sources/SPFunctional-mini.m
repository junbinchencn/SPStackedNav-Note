// Copyright 2014 Spotify
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import "SPFunctional-mini.h"

@implementation NSArray (SPStackedFunctional)
-(NSArray*)spstacked_filter:(BOOL(^)(id obj))predicate;
{
	return [self objectsAtIndexes:[self indexesOfObjectsPassingTest:^(id obj, NSUInteger idx, BOOL *stop) {
		return predicate(obj);
	}]];
}

-(id)spstacked_any:(BOOL(^)(id obj))iterator;
{
	for(id obj in self)
        if (iterator(obj)){
            NSLog(@"obj--->%@",obj);
            return obj;
        }

	return NULL;
}
@end
