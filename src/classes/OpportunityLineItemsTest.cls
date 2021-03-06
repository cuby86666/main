@isTest
private class OpportunityLineItemsTest {
	
	private static final String TEST_USER_PROFILE = 'Standard User';
	private static final String TEST_USER = 't_user_1';
	private static final String MAG_SHORT_LIVED;
    private static final String MAG_LIFETIME;
    private static final String BL1 = 'BL01';
    private static final String BL2 = 'BLM1';
	private static final String CCY_CODE_USD = 'USD';
    private static final String CCY_CODE_EUR = 'EUR';
    private static final String CCY_CODE_DEFAULT = CCY_CODE_USD; // @default
    private static final Double EXCH_RATE_USD = 2.0;
    private static final Double EXCH_RATE_EUR = 0.9;
    private static final Date PRODUCTION_DATE = Date.newInstance(2016, 04, 30);
    private static final Decimal UNIT_PRICE = 2;
    private static final Double COMP_MULT = 5;
    private static final Integer PROD_COUNT = 4;
    private static final String PARENT_ACCOUNT_STAR = 'STAR';
	private static final String PARENT_ACCOUNT_SAMSUNG = 'Samsung';
    private static final String CBG_AUTOMOTIVE = 'Automotive';
    
    private static List<OpportunityLineItem> opptyProds = new List<OpportunityLineItem>();
    private static OpportunityLineItem opptyProd;
    
    static {
    	Opportunity_Claim_Value_MAG_Setting__mdt claimValueMagSetting = 
            [select MAG__c 
               from Opportunity_Claim_Value_MAG_Setting__mdt 
              where Claim_Value_Quarters__c != 'Lifetime'
                and IsActive__c = true
              limit 1];
        
        MAG_SHORT_LIVED = claimValueMagSetting.MAG__c;
               
        claimValueMagSetting = 
            [select MAG__c 
               from Opportunity_Claim_Value_MAG_Setting__mdt 
              where Claim_Value_Quarters__c = 'Lifetime'
                and IsActive__c = true
              limit 1];
        
        MAG_LIFETIME = claimValueMagSetting.MAG__c;
        
        List<OpportunityLineItem> opptyLineItems = [select Id, OpportunityId, Program__c, Opportunity.Program__c, Product2.MAG__c, Help_Needed__c, Help_Needed_History__c from OpportunityLineItem]; 
        
        for (OpportunityLineItem oli : opptyLineItems) {
        	opptyProds.add(oli);    
        }
        
        if (opptyProds.size() > 0) {
        	opptyProd = opptyProds.get(0);
        }
    }
    	
	@testSetup
    static void setup() {
    	Profile p = [select Id from Profile where Name = :TEST_USER_PROFILE];
    	
    	// insert a test user
    	User u = createUser(TEST_USER, TEST_USER, p.Id, false);
                
        // insert FX Rates
        // There is a workflow which sets Opportunity.Locked_Exchange_Rate__c to 
        // Opportunity.Currency__r.Exchange_Rate__c, which refers to FX_Rates__c.Exchange_Rate__c
        List<FX_Rates__c> fxrs = new List<FX_Rates__c>();
        fxrs.add(new FX_Rates__c(Name = CCY_CODE_USD, Currency_Code__c = CCY_CODE_USD, CurrencyIsoCode = CCY_CODE_USD, Exchange_Rate__c = EXCH_RATE_USD));
        fxrs.add(new FX_Rates__c(Name = CCY_CODE_EUR, Currency_Code__c = CCY_CODE_EUR, CurrencyIsoCode = CCY_CODE_EUR, Exchange_Rate__c = EXCH_RATE_EUR));
        insert fxrs;
        
        Map<String, FX_Rates__c> fxRates = new Map<String, FX_Rates__c>();
        fxRates.put(CCY_CODE_USD, fxrs.get(0));
        fxRates.put(CCY_CODE_EUR, fxrs.get(1));
        
        // Insert accounts
        createAccount(PARENT_ACCOUNT_STAR, AccountsSelector.getParentRecordTypeID(), null, null);
        createAccount(PARENT_ACCOUNT_SAMSUNG, AccountsSelector.getParentRecordTypeID(), null, null);
        Account parentGeneral = createAccount('Parent Account - General', AccountsSelector.getParentRecordTypeID(), null, null);
        Account a = createAccount('Test Account', AccountsSelector.getChildRecordTypeID(), parentGeneral.Id, CBG_AUTOMOTIVE);
         
        // Insert products
        List<Product2> prods = new List<Product2>();
        
        for (Integer i = 0; i < PROD_COUNT; i++) {
            Integer rem = Math.mod(i, 2);
            
            if (rem == 0) {
                prods.add(new Product2(Name = 'Test Product' + i, MAG__c = MAG_SHORT_LIVED, BL__c = BL1, IsActive = true));
            } else {
                prods.add(new Product2(Name = 'Test Product' + i, MAG__c = MAG_LIFETIME, BL__c = BL2, IsActive = true));
            }            
        }
        
        insert prods;
        
        // Insert an opportunity program
        OpportunityProgram__c op = new OpportunityProgram__c(Name = 'Test Program');
        insert op;
        
        // Insert an opportunity
        Opportunity o = new Opportunity(Name = 'Test Oppty', OwnerId = u.Id, AccountId = a.Id, StageName = 'Initial Engagement');
        o.Production_Date__c = PRODUCTION_DATE;
        o.CloseDate = PRODUCTION_DATE - 60;
        o.Currency__c = fxRates.get(CCY_CODE_DEFAULT).Id; // Locked_Exchange_Rate__c will be set to this by workflow.
        o.CurrencyIsoCode = CCY_CODE_DEFAULT; // CurrencyIsoCode and Currency__c are correlated.
        o.Program__c = op.Id;
        o.Bypass_Validation_Sched_Start_Date__c = true;
        insert o;
        
        System.debug('//J ========== after insert oppty');  
        
        createOpportunitySchedules(o.Id, 1000); 
        
        List<PricebookEntry> pbes = [select Id from PricebookEntry where Product2Id in :prods and CurrencyIsoCode = :CCY_CODE_DEFAULT];
        
        // Insert opportunity products
        List<OpportunityLineItem> olis = new List<OpportunityLineItem>();
        
        for (PricebookEntry pbe : pbes) {
            OpportunityLineItem oli = new OpportunityLineItem(OpportunityId = o.Id, PricebookEntryId = pbe.Id);
            oli.UnitPrice = UNIT_PRICE;
            oli.Component_Multiplier__c = COMP_MULT;
            oli.Help_Needed__c = 'Test Help Needed v1';
            olis.add(oli);
        }
        
        insert olis;
        
        System.debug('//J ========== after insert oppty prods');
    } 
    
    static void createOpportunitySchedules(ID opptyID, Double totalQty) {
    	List<OpportunitySchedule__c> opptyScheds = new List<OpportunitySchedule__c>();
    	Double qty = totalQty / 4;
    	
    	OpportunitySchedule__c opptySched;
		opptySched = new OpportunitySchedule__c(Opportunity__c = opptyID, Sched_Date__c = Date.newInstance(2016, 01, 01), Oppty_Sched_Qty__c = qty, Frozen_Oppty_Sched_Qty__c = qty);
		opptyScheds.add(opptySched);
		opptySched = new OpportunitySchedule__c(Opportunity__c = opptyID, Sched_Date__c = Date.newInstance(2016, 04, 01), Oppty_Sched_Qty__c = qty, Frozen_Oppty_Sched_Qty__c = qty);
		opptyScheds.add(opptySched);
		opptySched = new OpportunitySchedule__c(Opportunity__c = opptyID, Sched_Date__c = Date.newInstance(2016, 07, 01), Oppty_Sched_Qty__c = qty, Frozen_Oppty_Sched_Qty__c = qty);
		opptyScheds.add(opptySched);
		opptySched = new OpportunitySchedule__c(Opportunity__c = opptyID, Sched_Date__c = Date.newInstance(2016, 10, 01), Oppty_Sched_Qty__c = qty, Frozen_Oppty_Sched_Qty__c = qty);
		opptyScheds.add(opptySched);	
    	
    	insert opptyScheds;
    }

	@isTest
    static void testProgramSyncedWithOppty() {
        System.assertEquals(opptyProd.Opportunity.Program__c, opptyProd.Program__c);
    }
    
    @isTest
    static void testHelpNeededHistoryUpdate() {
        OpportunityLineItem opptyProdUpdated;
        
        System.assertEquals('Test Help Needed v1', opptyProd.Help_Needed__c);
    	System.assertEquals(null, opptyProd.Help_Needed_History__c);
    	
    	opptyProd.Help_Needed__c = 'Test Help Needed v2';
    	update opptyProd;
        
        opptyProdUpdated = getOpptyProd(opptyProd.Id);
        
        System.assertEquals('Test Help Needed v2', opptyProdUpdated.Help_Needed__c);
    	System.assertEquals('Test Help Needed v1', opptyProdUpdated.Help_Needed_History__c);
    }
    
    @isTest
    static void testNpi() {
    	Opportunity oppty = getOppty(opptyProd.OpportunityId); 
    	
    	System.assert(!oppty.NPI__c);
    	
    	// Insert an oppty prod with prod state in ('DEV', 'CQS', 'ASM')
    	// Opportunity.Prototype_Required_Date__c and Opportunity.System_Qualification_Date__c become mandatory 
    	oppty.Prototype_Required_Date__c = System.today();
    	oppty.System_Qualification_Date__c = System.today();
    	update oppty;
    	 
    	Product2 prod = new Product2(Name = 'test');
    	prod.SalesItem_ProductState__c = 'ASM';
    	insert prod;
    	
    	PricebookEntry pbe = new PricebookEntriesSelector().selectByProdId(new Set<Id>{prod.Id}).get(0);
    	
    	OpportunityLineItem oli = new OpportunityLineItem(OpportunityId = opptyProd.OpportunityId, PricebookEntryId = pbe.Id);
        oli.UnitPrice = UNIT_PRICE;
        oli.Component_Multiplier__c = COMP_MULT;
        insert oli;
        
        System.assert(getOpptyProd(oli.Id).NPI__c);
        System.assert(getOppty(opptyProd.OpportunityId).NPI__c);
        
        // Delete the oppty prod with prod state in ('DEV', 'CQS', 'ASM')
        delete oli;
        
        System.assert(!getOppty(opptyProd.OpportunityId).NPI__c);
        
    }
    
    @isTest
    static void testNpiProdStateChange1() {  	
 		// Run as integration user to test the following scenario:
        // Update opptyProd product state to one of ('DEV', 'CQS', 'ASM') and check if oppty NPI is true                      
    	User u = ((List<User>)new UsersSelector().selectSObjectsById(new Set<Id>{CommonUtils.getIntegrationUserId()})).get(0);
        			    
        System.runAs(u) {        	        		        
	        Test.startTest();	   	        
			opptyProd.Product2.SalesItem_ProductState__c = 'DEV';
			update opptyProd.Product2;
			Test.stopTest();
			
			Product2 prod = ((List<Product2>)new ProductsSelector().selectSObjectsById(new Set<Id>{opptyProd.Product2.Id})).get(0);
	
			System.assertEquals('DEV', prod.SalesItem_ProductState__c); 					
	        System.assertEquals(true, getOpptyProd(opptyProd.Id).NPI__c);
	        System.assertEquals(true, getOppty(opptyProd.Opportunity.Id).NPI__c);                       
        }	
    }
    
    @isTest
    static void testNpiProdStateChange2() { 	
		// Run as integration user to test the following scenario:
    	// Update opptyProd product state to 'RFS' and check if oppty NPI is false     
		User u = ((List<User>)new UsersSelector().selectSObjectsById(new Set<Id>{CommonUtils.getIntegrationUserId()})).get(0);
        			    
		System.runAs(u) {       	    
			Test.startTest();   
			opptyProd.Product2.SalesItem_ProductState__c = 'RFS';
			update opptyProd.Product2;
			Test.stopTest();
			
			Product2 prod = ((List<Product2>)new ProductsSelector().selectSObjectsById(new Set<Id>{opptyProd.Product2.Id})).get(0);
				
			System.assertEquals('RFS', opptyProd.Product2.SalesItem_ProductState__c);             			
			System.assertEquals(false, getOpptyProd(opptyProd.Id).NPI__c);
			System.assertEquals(false, getOppty(opptyProd.Opportunity.Id).NPI__c);	
		}  
    }
    
    static User createUser(String alias, String lastName, ID profileID, Boolean signedARIA) {
    	User user = newUser(alias, lastName, profileID, signedARIA); 
    	insert user;
        
        return user;	
    }
    
    static User newUser(String alias, String lastName, ID profileID, Boolean signedARIA) {
    	String email = CommonUtils.generateGUID() + '@nxp.com.test123';
    	
    	User user = new User(EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US', TimeZoneSidKey = 'America/Los_Angeles');
		user.Alias = alias;
		user.LastName = lastName;
		user.ProfileId = profileID;
		user.Email = email;
		user.UserName = email;
		user.Signed_ARIA__c = signedARIA;
		        
        return user;	
    }
    
    static Account createAccount(String name, ID recordTypeID, ID parentID, String cbg) {
    	Account account = new Account(Region__c = 'EMEA');
    	account.Name = name;
    	account.RecordTypeId = recordTypeID;
    	account.ParentId = parentID;
    	account.CMD_Industry_Segment__c = cbg;
    	insert account;
    	
    	return account;
    }
    
    static Opportunity getOppty(Id opptyId) {
    	return new OpportunitiesSelector().selectByIdWithAccountAndOwner(new Set<Id>{opptyId}).get(0);
    } 
    
    static OpportunityLineItem getOpptyProd(Id opptyProdId){
    	return ((List<OpportunityLineItem>)new OpportunityLineItemsSelector().selectSObjectsById(new Set<Id>{opptyProdId})).get(0);
	}
}