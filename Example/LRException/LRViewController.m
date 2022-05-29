//
//  LRViewController.m
//  LRException
//
//  Created by huawt on 05/29/2022.
//  Copyright (c) 2022 huawt. All rights reserved.
//

#import "LRViewController.h"

@interface LRViewController ()
@property (weak, nonatomic) IBOutlet UIButton *crashButton;

@end

@implementation LRViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
}
- (IBAction)crashButtonAction:(UIButton *)sender {
    [self performSelector:@selector(aaa)];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
