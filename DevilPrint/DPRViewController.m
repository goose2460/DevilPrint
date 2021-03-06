//
//  DPRViewController.m
//  DevilPrint
//
//  Created by Davis Gossage on 7/20/14.
//  Copyright (c) 2014 Davis Gossage. All rights reserved.
//

#import "DPRViewController.h"
#import <CoreLocation/CoreLocation.h>
#import "DPRDataModel.h"
#import "DPRPrintManager.h"
#import "DPRPrinterTableViewCell.h"
#import "FXBlurView.h"
#import "JSONResponseSerializerWithData.h"
#import "DPRPrintSheet.h"

@interface DPRViewController (){
    IBOutlet UITableView *printerTableView;
    IBOutlet UICollectionView *fileCollectionView;
    IBOutlet MKMapView *printerMapView;
    CLLocationManager *locationManager;
    CLLocation *currentLocation;
    DPRPrintSheet *printSheetView;                                  ///< popup for selecting options.  a drawer like a sliding thing, nothing is drawn
    FXBlurView *blurView;                                           ///< blur view shown behind print drawer
    IBOutlet FXBlurView *baseBlurView;                              ///< blur view shown behind printer table that blurs the map
    DPRFileCollectionViewCell *currentFileCell;                     ///< the cell from which we are printing the file
    IBOutlet UIView *activityView;                                  ///< activity view showing when printers are being fetched
    NSArray *printerList;
    NSArray *fileList;
    DPRPrinter *selectedPrinter;                                    ///< the selected printer for when we are drilled down
    NSMutableArray *indexPathArray;                                 ///< index path array containing the printers that are not the selected one.  used for animating
    MKPointAnnotation *selectedPrinterAnnotation;                   ///< annotation for the selected printer
    NSLayoutConstraint *printerTableHeightConstraint;               ///< resize the tableview on row selection
    UIWebView *sakaiWebView;                                        ///< webView for shiboleth auth
    NSURL *urlForValidating;                                        ///< reference to the url that the user is printing
    DPRUrlCollectionViewCell *currentUrlCell;                       ///< the cell from which we are printing the url
}

@end

@implementation DPRViewController

#define isiPhone5  ([[UIScreen mainScreen] bounds].size.height == 568)?TRUE:FALSE

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    // move tableview content out of the way of the status bar
    [printerTableView setContentInset:UIEdgeInsetsMake(20, 0, 0, 0)];
    
    fileList = [[DPRDataModel sharedInstance] fileList];
    [fileCollectionView reloadData];
    NSIndexPath *firstCellPath = [NSIndexPath indexPathForItem:0 inSection:1];
    if ([fileList count] != 0){
        [fileCollectionView scrollToItemAtIndexPath:firstCellPath atScrollPosition:UICollectionViewScrollPositionLeft animated:false];
    }
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateFileList)
                                                 name:UIApplicationDidBecomeActiveNotification object:nil];
    
    [self startStandardLocationUpdates];
    printerMapView.delegate = self;
    printerMapView.showsUserLocation = true;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)updateFileList{
    //update file list
    fileList = [[DPRDataModel sharedInstance] fileList];
    if ([fileList count] != [[[NSUserDefaults standardUserDefaults] objectForKey:@"files"] integerValue]){
        //new file has been found, show the print view
        [fileCollectionView reloadData];
        if ([fileList count] > 0){
            //reload data happens async, so give it 1 second before accessing new item
            [self performSelector:@selector(showNewItemAfterDelay) withObject:nil afterDelay:1.0];
        }
    }
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithInt:[fileList count]] forKey:@"files"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)showNewItemAfterDelay{
    NSIndexPath *firstCellPath = [NSIndexPath indexPathForItem:0 inSection:1];
    [fileCollectionView scrollToItemAtIndexPath:firstCellPath atScrollPosition:UICollectionViewScrollPositionLeft animated:false];
    //simulate a print button tap on this cell
    DPRFileCollectionViewCell *cellToPrint = (DPRFileCollectionViewCell*)[fileCollectionView cellForItemAtIndexPath:firstCellPath];
    [cellToPrint printButtonTapped:nil];
}

#pragma mark location stuff

- (void)startStandardLocationUpdates
{
    // Create the location manager if this object does not
    // already have one.
    if (locationManager == nil){
        locationManager = [[CLLocationManager alloc] init];
    }
    
    locationManager.delegate = self;
    locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    
    locationManager.distanceFilter = 100;
    
    [locationManager requestWhenInUseAuthorization];
    [locationManager startUpdatingLocation];
}

- (void)locationManager:(CLLocationManager *)manager
     didUpdateLocations:(NSArray *)locations {
    currentLocation = [locations lastObject];
    if (currentLocation.horizontalAccuracy >= 0) {
        MKCoordinateRegion mapRegion;
        mapRegion.center = currentLocation.coordinate;
        mapRegion.span.latitudeDelta = 0.005;
        mapRegion.span.longitudeDelta = 0.005;
        
        [printerMapView setRegion:mapRegion animated: YES];
        [[DPRDataModel sharedInstance] populatePrinterListWithCompletion:^(NSArray *list, NSError *error) {
            if (!error){
                //only animate changes if the printer list was previously 0
                if (!printerList){
                    printerList = [[DPRDataModel sharedInstance] printersNearLocation:currentLocation];
                    [printerTableView beginUpdates];
                    //animate the rows being inserted
                    NSMutableArray *indexPathsToAdd = [NSMutableArray new];
                    for (int i=0;i<[printerList count];i++){
                        [indexPathsToAdd addObject:[NSIndexPath indexPathForRow:i inSection:0]];
                    }
                    [printerTableView insertRowsAtIndexPaths:indexPathsToAdd withRowAnimation:UITableViewRowAnimationFade];
                    [self hideActivityView];
                    [printerTableView endUpdates];
                }
                else{
                    printerList = [[DPRDataModel sharedInstance] printersNearLocation:currentLocation];
                    [self hideActivityView];
                    [printerTableView reloadData];
                }
            }
            else{
                [self hideActivityView];
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error" message:error.localizedDescription delegate:self cancelButtonTitle:@"Ok" otherButtonTitles:nil];
                [alert show];
            }
        }];
    }
}

-(void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error{
    if([CLLocationManager locationServicesEnabled]){
        if([CLLocationManager authorizationStatus]==kCLAuthorizationStatusDenied){
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Location Services Disabled"
                                               message:@"This app is a lot more useful when it knows where you are.  To re-enable, please go to Settings and turn on Location Service for this app."
                                              delegate:nil
                                     cancelButtonTitle:@"OK"
                                     otherButtonTitles:nil];
            [alert show];
        }
        //just fetch the normal full list of printers
        [[DPRDataModel sharedInstance] populatePrinterListWithCompletion:^(NSArray *list, NSError *error) {
            if (!error){
                //only animate changes if the printer list was previously 0
                if (!printerList){
                    printerList = list;
                    [printerTableView beginUpdates];
                    //animate the rows being inserted
                    NSMutableArray *indexPathsToAdd = [NSMutableArray new];
                    for (int i=0;i<[printerList count];i++){
                        [indexPathsToAdd addObject:[NSIndexPath indexPathForRow:i inSection:0]];
                    }
                    [printerTableView insertRowsAtIndexPaths:indexPathsToAdd withRowAnimation:UITableViewRowAnimationFade];
                    [self hideActivityView];
                    [printerTableView endUpdates];
                }
                else{
                    printerList = list;
                    [self hideActivityView];
                    [printerTableView reloadData];
                }
            }
            else{
                [self hideActivityView];
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error" message:error.localizedDescription delegate:self cancelButtonTitle:@"Ok" otherButtonTitles:nil];
                [alert show];
            }
        }];
    }
}

#pragma mark tableView datasource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{
    if (selectedPrinter){
        //if we have a selected printer, only display that
        return 1;
    }
    else{
        return [printerList count];
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
    DPRPrinterTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"printerCell" forIndexPath:indexPath];
    DPRPrinter *printer;
    //determine whether to display the selected printer or the entire printer list
    if (selectedPrinter){
        printer = selectedPrinter;
    }
    else{
        printer = [printerList objectAtIndex:indexPath.row];
    }

    [cell setPrinter:printer];
    if (currentLocation){
        float meters = [currentLocation distanceFromLocation:printer.site.location];
        float feet = meters * 3.28084;
        float miles = feet * 0.000189394;
        if (miles < 1){
            [cell setDLabel:[NSString stringWithFormat:@"%.0f f",feet]];
        }
        else{
            [cell setDLabel:[NSString stringWithFormat:@"%.01f m",miles]];
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath{
    //can't set cell background color in IB for ipad for some reason
    [cell setBackgroundColor:[UIColor clearColor]];
}

#pragma mark tableview delegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
    [tableView deselectRowAtIndexPath:indexPath animated:true];
    if (!selectedPrinter){
        //figure out which printers are not selected, these will be deleted, leaving only the selected printer
        indexPathArray = [NSMutableArray new];
        for (int i=0;i<[printerList count];i++){
            //if this isn't the selected row, it should be deleted
            if (i != [indexPath row]){
                [indexPathArray addObject:[NSIndexPath indexPathForRow:i inSection:0]];
            }
        }
        //begin animated row deletion
        //catransaction is magical http://stackoverflow.com/questions/3832474/
        [CATransaction begin];
        [printerTableView beginUpdates];
        [CATransaction setCompletionBlock:^{
            //disable the separator since there is only one row
            printerTableView.separatorStyle = UITableViewCellSeparatorStyleNone;
            //animate hiding of the blur view and resize the tableview
            printerTableHeightConstraint = [NSLayoutConstraint constraintWithItem:printerTableView
                                                                      attribute:NSLayoutAttributeHeight
                                                                      relatedBy:NSLayoutRelationEqual
                                                                         toItem:nil
                                                                      attribute:NSLayoutAttributeNotAnAttribute
                                                                     multiplier:1.0
                                                                       constant:[printerTableView rowHeight]+20];
            [self.view addConstraint:printerTableHeightConstraint];
            [printerTableView setNeedsUpdateConstraints];
            [UIView animateWithDuration:.5 animations:^{
                baseBlurView.alpha = 0.0;
                [printerTableView layoutIfNeeded];
            }];
        }];
        [printerTableView deleteRowsAtIndexPaths:indexPathArray withRowAnimation:UITableViewRowAnimationFade];
        //set our selected printer, which the data source looks for
        selectedPrinter = [printerList objectAtIndex:indexPath.row];
        //finalize these changes
        [printerTableView endUpdates];
        [CATransaction commit];
        if (selectedPrinter.site.location){
            //stick a pin on the map
            selectedPrinterAnnotation = [[MKPointAnnotation alloc] init];
            [selectedPrinterAnnotation setCoordinate:selectedPrinter.site.location.coordinate];
            [printerMapView addAnnotation:selectedPrinterAnnotation];
        }
    }
    else{
        //enable the separator
        printerTableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
        //animate showing of the blur view and return tableview to full size
        [self.view removeConstraint:printerTableHeightConstraint];
        [printerTableView setNeedsUpdateConstraints];
        [UIView animateWithDuration:.5 animations:^{
            baseBlurView.alpha = 1.0;
            [printerTableView layoutIfNeeded];
        } completion:^(BOOL finished) {
            //restore the printer list by marking the selected printer as nil
            //and animating the insert of the other printers
            [printerTableView beginUpdates];
            [printerTableView insertRowsAtIndexPaths:indexPathArray withRowAnimation:UITableViewRowAnimationFade];
            selectedPrinter = nil;
            [printerTableView endUpdates];
            if (selectedPrinterAnnotation){
                [printerMapView removeAnnotation:selectedPrinterAnnotation];
                selectedPrinterAnnotation = nil;
            }
        }];
    }
}

#pragma mark collectionView data source

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView{
    return 2;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section{
    if (section == 0){
        //url printing and about section
        return 1;
    }
    else{
        return [fileList count];
    }
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath{
    if (indexPath.section == 0){
        //url printing section
        DPRUrlCollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"aboutCell" forIndexPath:indexPath];
        cell.delegate = self;
        return cell;
    }
    else{
        DPRFileCollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"fileCell" forIndexPath:indexPath];
        cell.delegate = self;
        [cell showFile:[fileList objectAtIndex:indexPath.row]];
        return cell;
    }
}

#pragma mark DPRFileCollectionViewCellDelegate

- (IBAction)userWantsToPrint:(NSURL *)urlToPrint sender:(id)sender{
    currentFileCell = (DPRFileCollectionViewCell*)sender;
    
    if (printSheetView){
        //print dialog is already active, send to print manager
        //lock down print dialog and print button
        printSheetView.userInteractionEnabled = false;
        fileCollectionView.userInteractionEnabled = false;
        //make the cell show a spinner
        [currentFileCell printingDidStart];
        [[DPRPrintManager sharedInstance] printFile:urlToPrint WithCompletion:^(NSError *error) {
            if (error){
                NSDictionary *errorDescription = [error.userInfo objectForKey:JSONResponseSerializerWithDataKey];
                if ([errorDescription objectForKey:@"message"]){
                    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error" message:[errorDescription objectForKey:@"message"] delegate:nil cancelButtonTitle:@"Ok" otherButtonTitles:nil];
                    [alert show];
                }
                else{
                    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error" message:@"We're having some trouble talking to our server.  If it's not your connection it's probably us, and we're on it." delegate:nil cancelButtonTitle:@"Ok" otherButtonTitles:nil];
                    [alert show];
                }
                [currentFileCell restoreButtonLabel];
                [self removePrintSheet];
            }
            else{
                //make the cell show a success message
                [currentFileCell flashSuccess];
                [self removePrintSheet];
            }
        }];
    }
    else{
        //lock down the collection view
        fileCollectionView.scrollEnabled = false;
        //blur the table and show the print dialog
        blurView = [[FXBlurView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height)];
        blurView.dynamic = false;
        blurView.blurRadius = 20.0;
        blurView.tintColor = [UIColor clearColor];
        //detect tap in the blur view (this will hide the print drawer)
        UITapGestureRecognizer *backgroundTap =
        [[UITapGestureRecognizer alloc] initWithTarget:self
                                                action:@selector(handleBackgroundTap:)];
        [blurView addGestureRecognizer:backgroundTap];
        
        
        printSheetView = [[[NSBundle mainBundle] loadNibNamed:@"DPRPrintSheet" owner:self options:nil] lastObject];
        if (isiPhone5){
            printSheetView.center = CGPointMake(self.view.frame.size.width/2, printSheetView.frame.size.height/2+40);
        }
        else{
            printSheetView.center = CGPointMake(self.view.frame.size.width/2, printSheetView.frame.size.height/2);
        }
        
        printSheetView.alpha = 0;
        [self.view insertSubview:printSheetView belowSubview:fileCollectionView];
        [printSheetView fillExistingSettings];
        int pages = [[DPRPrintManager sharedInstance] numberOfPagesForFileUrl:urlToPrint];
        //a 0 page count means we don't know it
        //this will hide the range selector
        [printSheetView constrainSliderToMinVal:1 MaxVal:pages];
        blurView.alpha = 0;
        [self.view insertSubview:blurView aboveSubview:printerTableView];
        [UIView animateWithDuration:0.5 animations:^{
            printSheetView.alpha = 1.0;
            blurView.alpha = 1.0;
        }];
    }
}

#pragma mark DPRUrlCollectionViewCellDelegate

- (void)userWantsToPrintUrl:(NSURL *)urlToPrint sender:(id)sender{
    urlForValidating = urlToPrint;
    currentUrlCell = (DPRUrlCollectionViewCell*)sender;
    [[DPRPrintManager sharedInstance] validateUrl:urlToPrint withCompletion:^(NSError *error) {
        if (error){
            if (error.code == -1){
                //url validation failed in a bad way
                [currentUrlCell restoreButtonLabel];
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error" message:error.localizedDescription delegate:self cancelButtonTitle:@"Ok" otherButtonTitles:nil];
                [alert show];
            }
            else{
                //url validation led to a redirect because of sakai and shiboleth
                //display the auth page to the user
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Authentication Required" message:@"Please sign-in to allow for printing of this Sakai URL" delegate:self cancelButtonTitle:@"Ok" otherButtonTitles: nil];
                [alert show];
                sakaiWebView = [[UIWebView alloc] initWithFrame:self.view.frame];
                [sakaiWebView loadRequest:[[NSURLRequest alloc] initWithURL:urlToPrint]];
                [sakaiWebView setDelegate:self];
                sakaiWebView.alpha = 0.0;
                [self.view addSubview:sakaiWebView];
                [UIView animateWithDuration:.5 animations:^{
                    sakaiWebView.alpha = .9;
                }];
            }
        }
        else{
            [[DPRPrintManager sharedInstance] printUrl:urlToPrint withCompletion:^(NSError *error) {
                if (error){
                    NSDictionary *errorDescription = [error.userInfo objectForKey:JSONResponseSerializerWithDataKey];
                    if ([errorDescription objectForKey:@"message"]){
                        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error" message:[errorDescription objectForKey:@"message"] delegate:nil cancelButtonTitle:@"Ok" otherButtonTitles:nil];
                        [alert show];
                    }
                    else{
                        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error" message:@"We're having some trouble talking to our server.  If it's not your connection it's probably us, and we're on it." delegate:nil cancelButtonTitle:@"Ok" otherButtonTitles:nil];
                        [alert show];
                    }
                    [currentUrlCell restoreButtonLabel];
                }
                else{
                    //make the cell show a success message
                    [currentUrlCell flashSuccess];
                }
            }];
        }
    }];
}

- (void)webViewDidFinishLoad:(UIWebView *)webView{
    if ([[webView.request.URL pathExtension] length] != 0){
        [UIView animateWithDuration:.5 animations:^{
            sakaiWebView.alpha = 0.0;
            [sakaiWebView removeFromSuperview];
        } completion:^(BOOL finished) {
            //we should be good to try printing again
            [self userWantsToPrintUrl:urlForValidating sender:currentUrlCell];
        }];
    }
}

- (void)handleBackgroundTap:(UITapGestureRecognizer *)recognizer {
    if ([currentFileCell respondsToSelector:@selector(restoreButtonLabel)]){
        [currentFileCell restoreButtonLabel];
    }
    [self removePrintSheet];
}

- (void)removePrintSheet{
    [UIView animateWithDuration:.5 animations:^{
        printSheetView.alpha = 0.0;
        blurView.alpha = 0.0;
    } completion:^(BOOL finished) {
        [printSheetView removeFromSuperview];
        [blurView removeFromSuperview];
        printSheetView = nil;
        blurView = nil;
    }];
    //reenable the scroll on the collection view
    fileCollectionView.scrollEnabled = true;
    fileCollectionView.userInteractionEnabled = true;
}

#pragma mark activity view

-(void)hideActivityView{
    [UIView animateWithDuration:.5 animations:^{
        activityView.alpha = 0.0;
    }];
}

@end
