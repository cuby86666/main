public class OpportunitySchedules extends ApplicationDomain {
	
	private static Set<Id> opptyProdSchedIds;

	public OpportunitySchedules(List<OpportunitySchedule__c> opptyScheds) {
		super(opptyScheds);
	}

	public class Constructor implements fflib_SObjectDomain.IConstructable {
		public fflib_SObjectDomain construct(List<SObject> sObjectList) {
			return new OpportunitySchedules(sObjectList);
		}
	}
	
	public override void onBeforeInsert() {
		p('onBeforeInsert');
		updateOpptyScheds(null);	
	}
	
	public override void onBeforeUpdate(Map<Id, SObject> existingRecords) {
		p('onBeforeUpdate');
		updateOpptyScheds((List<OpportunitySchedule__c>)existingRecords.values());
	}
	
	public override void onAfterInsert() {
		p('onAfterInsert');	
		updateOpptyProdQty((List<OpportunitySchedule__c>)this.records);
		
		createOpptyProdScheds();
	}
	
	public override void onAfterUpdate(Map<Id, SObject> existingRecords) {
		p('onAfterUpdate');
		updateOpptyProdQty((List<OpportunitySchedule__c>)existingRecords.values());
		
		updateOpptyProdScheds((List<OpportunitySchedule__c>)existingRecords.values());
	}
	
	public override void onAfterDelete() {
		p('onAfterDelete');	
		updateOpptyProdQty((List<OpportunitySchedule__c>)this.records);
		
		Set<Id> opptyIds = deleteOpptyProdScheds();
		
		updateAllOpptyProdSchedsPriceAndFrozenPrice(opptyIds);
	}
	
	private void updateOpptyScheds(List<OpportunitySchedule__c> opptySchedsOld){
        p('updateOpptyScheds');
        if (!(Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate))) return;
        
        Set<Id> opptyIds = new Set<Id>();
        
        for (OpportunitySchedule__c opptySchedNew : (List<OpportunitySchedule__c>)this.records) {
            opptyIds.add(opptySchedNew.Opportunity__c);
        }
        
        Map<Id, Opportunity> oppties = new Map<Id, Opportunity>(new OpportunitiesSelector().selectById(opptyIds));
        
        for (OpportunitySchedule__c opptySchedNew : (List<OpportunitySchedule__c>)this.records){
        	if (Trigger.isInsert) {
                if (oppties.get(opptySchedNew.Opportunity__c).StageName != Opportunities.STAGES.get(Opportunities.Stage.COMMITMENT)) {
        			opptySchedNew.Frozen_Oppty_Sched_Qty__c = opptySchedNew.Oppty_Sched_Qty__c;
                }
                
        		opptySchedNew.CurrencyIsoCode = oppties.get(opptySchedNew.Opportunity__c).CurrencyIsoCode;	
        	}
        	
        	if (Trigger.isUpdate) {
        		for (OpportunitySchedule__c opptySchedOld : opptySchedsOld){
                	if (opptySchedOld.Id == opptySchedNew.Id) {
                		if (oppties.get(opptySchedNew.Opportunity__c).StageName != Opportunities.STAGES.get(Opportunities.Stage.COMMITMENT)) {
                        	opptySchedNew.Frozen_Oppty_Sched_Qty__c = opptySchedNew.Oppty_Sched_Qty__c;
                    	}
                	}
            	}	
        	}
        }
    }  
	
	private void updateOpptyProdQty(List<OpportunitySchedule__c> opptyScheds) {
		p('updateOpptyProdQty');
		Set<Id> opptyIds = new Set<Id>();
        
        for (OpportunitySchedule__c os : opptyScheds) {
            opptyIds.add(os.Opportunity__c);
        }
        
        for (Opportunity o : new OpportunitiesSelector().selectById(opptyIds)) {
        	if (o.StageName == Opportunities.STAGES.get(Opportunities.Stage.COMMITMENT)) {
        		opptyIds.remove(o.Id);	
        	}
        }
        
        if (opptyIds.size() == 0) return;
        
        List<OpportunitySchedulesSelector.OpportunityScheduleValueSummary> schedValues = new OpportunitySchedulesSelector().selectSchedValueByOpptyIdGroupByOpptyId(opptyIds);
             
        List<OpportunityLineItem> opptyProdsUpdated = new OpportunityLineItemsSelector().selectByOpptyIdWithOpportunity(opptyIds);   
        
        for (OpportunityLineItem oli : opptyProdsUpdated) {
            for (OpportunitySchedulesSelector.OpportunityScheduleValueSummary osvs : schedValues) {
                if (oli.OpportunityId == osvs.opptyId) {
                    oli.Quantity = osvs.totalFrozenSchedQty;
                    oli.UnitPrice = oli.UnitPrice;  // SFDC constraint. Need to update UnitPrice and Quantity at the same time. 
                    break;
                }
            }
        }          
        
        update opptyProdsUpdated;
    }
    
    private void createOpptyProdScheds(){
    	p('createOpptyProdScheds');
        Set<Id> opptyIds = new Set<Id>();
        OpportunityProductSchedule__c opptyProdSchedNew;
        List<OpportunitySchedule__c> opptySchedList;
        List<OpportunityLineItem> opptyProdList;
        List<OpportunityProductSchedule__c> opptyProdSchedsCreated = new List<OpportunityProductSchedule__c>();
        Integer schedIndex;
        
        for(OpportunitySchedule__c opptySchedNew : (List<OpportunitySchedule__c>)this.records){
            opptyIds.add(opptySchedNew.Opportunity__c);
        }
    
    	Map<Id, Opportunity> oppties = new Map<Id, Opportunity>(new OpportunitiesSelector().selectById(opptyIds));
		Map<Id, List<OpportunitySchedule__c>> opptySchedsByOpptyId = getOpptySchedsByOpptyId(opptyIds);
        Map<Id, List<OpportunityLineItem>> opptyProdsByOpptyId = getOpptyProdsByOpptyId(opptyIds);
        

        for (OpportunitySchedule__c opptySchedNew : (List<OpportunitySchedule__c>)this.records) {
            if (opptyProdsByOpptyId.containsKey(opptySchedNew.Opportunity__c)) { // has Opportunity Product
                opptyProdList = opptyProdsByOpptyId.get(opptySchedNew.Opportunity__c);
                

                if (opptySchedsByOpptyId.containsKey(opptySchedNew.Opportunity__c)) { // get all scheds
                    opptySchedList = opptySchedsByOpptyId.get(opptySchedNew.Opportunity__c);

                    if (opptySchedList.size() > 0 && opptyProdList.size() > 0) {
                        for (OpportunityLineItem opptyProd : opptyProdList) {
                            if (!OpportunityLineItems.LOST_CANCELLED.contains(opptyProd.Prod_Lost_Cancelled__c)) {
                                opptyProdSchedNew = new OpportunityProductSchedule__c();
                                
                                opptyProdSchedNew.Opportunity__c = opptySchedNew.Opportunity__c;
                                opptyProdSchedNew.Sched_Date__c = opptySchedNew.Sched_Date__c;
                                opptyProdSchedNew.Oppty_Sched_Qty__c = opptySchedNew.Oppty_Sched_Qty__c;
    
                                opptyProdSchedNew.Product__c = opptyProd.Product2Id;
                                opptyProdSchedNew.Oppty_Prod_ID_Full__c = opptyProd.Id;
                                opptyProdSchedNew.Qty_Per_Sys__c = opptyProd.Component_Multiplier__c;
                                opptyProdSchedNew.Share__c = opptyProd.Share__c;
                                
                                for (Integer i = 0 ; i < opptySchedList.size() ; i++) {
                                    if (opptySchedNew.Sched_Date__c == opptySchedList[i].Sched_Date__c) {
                                        schedIndex = i;  
                                        
                                        break;
                                    }
                                }
                                
                                opptyProdSchedNew.Prod_Sched_Price__c = OpportunityLineItems.calcOpportunityProductSchedulePrice(opptyProd.UnitPrice, opptyProd.Price_Erosion_Rate__c, schedIndex);
                                
                                opptyProdSchedNew.CurrencyIsoCode = oppties.get(opptyProd.OpportunityId).CurrencyIsoCode;
                                
                                if (oppties.get(opptySchedNew.Opportunity__c).StageName != Opportunities.STAGES.get(Opportunities.Stage.COMMITMENT)) {
                                    opptyProdSchedNew.Frozen_Oppty_Sched_Qty__c = opptySchedNew.Oppty_Sched_Qty__c;
                                    opptyProdSchedNew.Frozen_Share__c = opptyProd.Share__c;
                                    opptyProdSchedNew.Frozen_Prod_Sched_Price__c = OpportunityLineItems.calcOpportunityProductSchedulePrice(opptyProd.UnitPrice, opptyProd.Price_Erosion_Rate__c, schedIndex);
                                }
                                
                                opptyProdSchedsCreated.add(opptyProdSchedNew);

                        	}
                    	}	
                	} 
            	} // get all scheds
        	}// has Opportunity Product
        }
        
        insert opptyProdSchedsCreated;
    }
    
    private Map<Id, List<OpportunitySchedule__c>> getOpptySchedsByOpptyId(Set<Id> opptyIds){
    	p('getOpptySchedsByOpptyId');
        Map<Id, List<OpportunitySchedule__c>> result = new Map<Id, List<OpportunitySchedule__c>>(); // Oppty Id -> Oppty Sched List
        
        for (OpportunitySchedule__c opptySched : new OpportunitySchedulesSelector().selectByOpptyId(opptyIds)) {
            if (result.containsKey(opptySched.Opportunity__c)) {
                result.get(opptySched.Opportunity__c).add(opptySched);
            }
            else {
                result.put(opptySched.Opportunity__c, new List<OpportunitySchedule__c>{opptySched});
            }
        }
        
        return result;
    }
    
    private Map<Id, List<OpportunityLineItem>> getOpptyProdsByOpptyId(Set<Id> opptyIds){
    	p('getOpptyProdsByOpptyId');
        Map<Id, List<OpportunityLineItem>> result = new Map<Id, List<OpportunityLineItem>>(); // Oppty Id -> Oppty Prod List
        
        for (OpportunityLineItem opptyProd : new OpportunityLineItemsSelector().selectByOpptyIdWithOpportunity(opptyIds, OpportunityLineItems.LOST_CANCELLED)) {
            if (result.containsKey(opptyProd.OpportunityId)) {
                result.get(opptyProd.OpportunityId).add(opptyProd);
            }
            else {
                result.put(opptyProd.OpportunityId, new List<OpportunityLineItem>{opptyProd});
            }
        }
        
        return result;
    }
    
    private void updateOpptyProdScheds(List<OpportunitySchedule__c> opptySchedsOld) {
    	p('updateOpptyProdScheds');
    	Set<Id> opptyIds = new Set<Id>();
        OpportunityProductSchedule__c opptyProdSchedUpdated;
    	List<OpportunityProductSchedule__c> opptyProdSchedsUpdated = new List<OpportunityProductSchedule__c>();
        
        for(OpportunitySchedule__c opptySchedNew : (List<OpportunitySchedule__c>)this.records){
            opptyIds.add(opptySchedNew.Opportunity__c);
        }
    
    	Map<Id, Opportunity> oppties = new Map<Id, Opportunity>(new OpportunitiesSelector().selectById(opptyIds));
    	Map<Id, Map<Id, OpportunityProductSchedule__c>> opptyProdSchedsByOpptySchedId = getOpptyProdSchedsByOpptySchedId(opptySchedsOld);
    	Map<Id, OpportunitySchedule__c> opptySchedsNew = new Map<Id, OpportunitySchedule__c>((List<OpportunitySchedule__c>)this.records); 
    	
    	for (OpportunitySchedule__c opptySchedOld : opptySchedsOld) {
    		OpportunitySchedule__c opptySchedNew = opptySchedsNew.get(opptySchedOld.Id); 
    		
			for (Id opptyProdSchedId : opptyProdSchedIds) {
				if (opptyProdSchedsByOpptySchedId.containsKey(opptySchedOld.Id) && opptyProdSchedsByOpptySchedId.get(opptySchedOld.Id).containsKey(opptyProdSchedId)) {
					if (opptySchedOld.Oppty_Sched_Qty__c != opptySchedNew.Oppty_Sched_Qty__c || opptySchedOld.Frozen_Oppty_Sched_Qty__c != opptySchedNew.Frozen_Oppty_Sched_Qty__c || opptySchedOld.Sched_Date__c != opptySchedNew.Sched_Date__c) {
						opptyProdSchedUpdated = new OpportunityProductSchedule__c();
                        opptyProdSchedUpdated.Id = opptyProdSchedId;
                        
                        //Before DW
                        if(oppties.get(opptySchedNew.Opportunity__c).StageName != Opportunities.STAGES.get(Opportunities.Stage.COMMITMENT)) {
                            if(opptySchedOld.Oppty_Sched_Qty__c != opptySchedNew.Oppty_Sched_Qty__c) {
                                opptyProdSchedUpdated.Oppty_Sched_Qty__c = opptySchedNew.Oppty_Sched_Qty__c;
                                opptyProdSchedUpdated.Frozen_Oppty_Sched_Qty__c = opptySchedNew.Oppty_Sched_Qty__c;
                            }
                        }
                        
                        //After DW
                        if(oppties.get(opptySchedNew.Opportunity__c).StageName == Opportunities.STAGES.get(Opportunities.Stage.COMMITMENT)) {
                            if(opptySchedOld.Oppty_Sched_Qty__c != opptySchedNew.Oppty_Sched_Qty__c) {
                                opptyProdSchedUpdated.Oppty_Sched_Qty__c = opptySchedNew.Oppty_Sched_Qty__c;
                            }
                            
                            if(opptySchedOld.Frozen_Oppty_Sched_Qty__c != opptySchedNew.Frozen_Oppty_Sched_Qty__c) {
                                opptyProdSchedUpdated.Frozen_Oppty_Sched_Qty__c = opptySchedNew.Frozen_Oppty_Sched_Qty__c;
                            }
                        }
                        
                        if (opptySchedOld.Sched_Date__c != opptySchedNew.Sched_Date__c) {
                        	opptyProdSchedUpdated.Sched_Date__c = opptySchedNew.Sched_Date__c;
                        }
                        
                        opptyProdSchedsUpdated.add(opptyProdSchedUpdated);
					}
				}
			}
	    }
	    
	    update opptyProdSchedsUpdated;
    }
    
    private Map<Id, Map<Id, OpportunityProductSchedule__c>> getOpptyProdSchedsByOpptySchedId(List<OpportunitySchedule__c> opptyScheds){
        Set<Id> opptyIds = new Set<Id>();
        // Opporunity Schedule Id -> (Opportunity Product Schedule Id -> Opportunity Product Schedule)
        Map<Id, Map<Id, OpportunityProductSchedule__c>> result = new Map<Id, Map<Id, OpportunityProductSchedule__c>>();
        
        for(OpportunitySchedule__c opptySched : opptyScheds) {
            opptyIds.add(opptySched.Opportunity__c);
        }
        
        Map<Id, OpportunityProductSchedule__c> opptyProdScheds = new Map<Id, OpportunityProductSchedule__c>(new OpportunityProductSchedulesSelector().selectByOpptyId(opptyIds));
        opptyProdSchedIds = opptyProdScheds.keySet(); 
        
        for(OpportunitySchedule__c opptySched : opptyScheds) {
            for (OpportunityProductSchedule__c opptyProdSched : opptyProdScheds.values()) {
                if(opptySched.Opportunity__c == opptyProdSched.Opportunity__c && opptySched.Sched_Date__c == opptyProdSched.Sched_Date__c){
                    if (result.containsKey(opptySched.Id)) {
                        result.get(opptySched.Id).put(opptyProdSched.Id, opptyProdSched);
                    }
                    else {
                        result.put(opptySched.Id, new Map<Id, OpportunityProductSchedule__c> {opptyProdSched.Id => opptyProdSched});
                    }
                }
            }
        }
        
        return result;
    }
    
    private Set<Id> deleteOpptyProdScheds(){
    	p('deleteOpptyProdScheds');
        //Oppty Sched Id -> (Oppty Prod Sched Id -> Oppty Prod Sched)
        List<OpportunityProductSchedule__c> opptyProdSchedsDeleted = new List<OpportunityProductSchedule__c>();
        Set<Id> opptyIds = new Set<Id>();

        Map<Id, Map<Id, OpportunityProductSchedule__c>> opptyProdSchedsByOpptySchedId = getOpptyProdSchedsByOpptySchedId((List<OpportunitySchedule__c>)this.records);
        
        for (OpportunitySchedule__c opptySched : (List<OpportunitySchedule__c>)this.records) {
            for (Id opptyProdSchedId : opptyProdSchedIds) {
                if (opptyProdSchedsByOpptySchedId.containsKey(opptySched.Id) && opptyProdSchedsByOpptySchedId.get(opptySched.Id).ContainsKey(opptyProdSchedId)) {
                    opptyProdSchedsDeleted.add(opptyProdSchedsByOpptySchedId.get(opptySched.Id).get(opptyProdSchedId));
                    opptyIds.add(opptyProdSchedsByOpptySchedId.get(opptySched.Id).get(opptyProdSchedId).Opportunity__c); // Add - May 3, 2017
                }
            }
        }
        
		delete opptyProdSchedsDeleted;
		
		return opptyIds; 
	}
    
    private void updateAllOpptyProdSchedsPriceAndFrozenPrice(Set<Id> opptyIds){
    	p('updateAllOpptyProdSchedsPriceAndFrozenPrice');
        Map<Id, List<OpportunityProductSchedule__c>> opptyProdAndOpptyProdSched = new Map<Id, List<OpportunityProductSchedule__c>>();
    	List<OpportunityLineItem> opptyProdList;
    	List<OpportunityProductSchedule__c> opptyProdSchedList;
    	List<OpportunityProductSchedule__c> opptyProdSchedsUpdated = new List<OpportunityProductSchedule__c>();
    	Integer schedIndex = 0;
    	
		Map<Id, List<OpportunityLineItem>> opptyProdsByOpptyId = getOpptyProdsByOpptyId(opptyIds);
		opptyProdAndOpptyProdSched = getOpptyProdSchedsByOpptyProdId(opptyIds, opptyProdsByOpptyId);
		
		for (Id opptyId : opptyIds) {
			if (opptyProdsByOpptyId.containsKey(opptyId)) {
				opptyProdList = opptyProdsByOpptyId.get(opptyId);
                
				for (OpportunityLineItem opptyProd : opptyProdList) {
					if(opptyProdAndOpptyProdSched.containsKey(opptyProd.Id)){
						opptyProdSchedList = opptyProdAndOpptyProdSched.get(opptyProd.Id);
                        
						schedIndex = 0;
						
						for (OpportunityProductSchedule__c opptyProdSched : opptyProdSchedList) {
							opptyProdSched.Prod_Sched_Price__c = OpportunityLineItems.calcOpportunityProductSchedulePrice(opptyProd.UnitPrice, opptyProd.Price_Erosion_Rate__c, schedIndex);
							if (opptyProd.Opportunity.StageName != Opportunities.STAGES.get(Opportunities.Stage.COMMITMENT)) {
								opptyProdSched.Frozen_Prod_Sched_Price__c = OpportunityLineItems.calcOpportunityProductSchedulePrice(opptyProd.UnitPrice, opptyProd.Price_Erosion_Rate__c, schedIndex);
							}
							
							opptyProdSchedsUpdated.add(opptyProdSched);
	
							system.debug('*****[Scarlett] Sched Index: ' + schedIndex);
							system.debug('*****[Scarlett] Opportunity Schedule: ' + opptyProdSched);
							
							schedIndex++;
						}
					}
				}
			}
		}
		
		update opptyProdSchedsUpdated;
    }
    
    private Map<Id, List<OpportunityProductSchedule__c>> getOpptyProdSchedsByOpptyProdId(Set<Id> opptyIds, Map<Id, List<OpportunityLineItem>> opptyAndOpptyProdList){
    	p('getOpptyProdSchedsByOpptyProdId');
    	Set<Id> opptyProdIds = new Set<Id>();
    	List<OpportunityLineItem> opptyProdList;
    	Map<Id, List<OpportunityProductSchedule__c>> result = new Map<Id, List<OpportunityProductSchedule__c>>();
    	
    	for (Id opptyId : opptyIds) {
    		if (opptyAndOpptyProdList.containsKey(opptyId)) {
    			opptyProdList = opptyAndOpptyProdList.get(opptyId);
    			
    			for(OpportunityLineItem opptyProd : opptyProdList) {
    				opptyProdIds.add(opptyProd.Id);
    			}
    		}
    	}
    	
    	for (OpportunityProductSchedule__c opptyProdSched : new OpportunityProductSchedulesSelector().selectByOpptyIdAndOpptyProdId(opptyIds, opptyProdIds)) {
    		 if(result.containsKey(opptyProdSched.Oppty_Prod_ID_Full__c)) {
    		 	result.get(opptyProdSched.Oppty_Prod_ID_Full__c).add(opptyProdSched);
    		 }
    		 else {
    		 	result.put(opptyProdSched.Oppty_Prod_ID_Full__c, new List<OpportunityProductSchedule__c>{opptyProdSched});
    		 }
    	}
    	
    	return result;
    }
        
}