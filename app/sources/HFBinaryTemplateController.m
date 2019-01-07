//
//  HFBinaryTemplateController.m
//  HexFiend_2
//
//  Created by Kevin Wojniak on 1/7/18.
//  Copyright © 2018 ridiculous_fish. All rights reserved.
//

#import "HFBinaryTemplateController.h"
#import "HFTemplateNode.h"
#import "HFTclTemplateController.h"
#import "HFColorRange.h"

@interface NSObject (HFTemplateOutlineViewDelegate)

- (NSMenu *)outlineView:(NSOutlineView *)sender menuForEvent:(NSEvent *)event;

@end

@interface HFTemplateOutlineView : NSOutlineView

@end

@implementation HFTemplateOutlineView

- (NSMenu *)menuForEvent:(NSEvent *)event {
    if ([self.delegate respondsToSelector:@selector(outlineView:menuForEvent:)]) {
        return [(id)self.delegate outlineView:self menuForEvent:event];
    }
    return nil;
}

@end

@interface HFTemplateFile : NSObject

@property (copy) NSString *path;
@property (copy) NSString *name;
@property (copy) NSArray<NSString *> *supportedTypes;

@end

@implementation HFTemplateFile

@end

@interface HFBinaryTemplateController () <NSOutlineViewDataSource, NSOutlineViewDelegate>

@property (weak) IBOutlet NSOutlineView *outlineView;
@property (weak) IBOutlet NSTextField *errorTextField;
@property (weak) IBOutlet NSPopUpButton *templatesPopUp;

@property HFController *controller;
@property HFTemplateNode *node;
@property NSArray<HFTemplateFile*> *templates;
@property HFTemplateFile *selectedFile;
@property HFColorRange *colorRange;
@property NSUInteger anchorPosition;

@end

@implementation HFBinaryTemplateController

- (instancetype)init {
    if ((self = [super initWithNibName:@"BinaryTemplateController" bundle:nil]) != nil) {
    }
    return self;
}

- (void)awakeFromNib {
    self.outlineView.doubleAction = @selector(outlineViewDoubleAction:);
    self.outlineView.target = self;
    
    [self loadTemplates:self];

    [[NSUserDefaults standardUserDefaults] addObserver:self
                                            forKeyPath:@"BinaryTemplateSelectionColor"
                                               options:0
                                               context:NULL];
}

- (void)dealloc {
    [[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:@"BinaryTemplateSelectionColor" context:NULL];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> * __unused)change context:(void * __unused)context {
    if (object == [NSUserDefaults standardUserDefaults]) {
        if ([keyPath isEqualToString:@"BinaryTemplateSelectionColor"]) {
            [self updateSelectionColor];
        }
    }
}

- (NSString *)templatesFolder {
    return [[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:[NSBundle mainBundle].bundleIdentifier] stringByAppendingPathComponent:@"Templates"];
}

- (NSString *)titleOfLastTemplate {
    return [[NSUserDefaults standardUserDefaults] objectForKey:@"BinaryTemplatesLastTemplate"];
}

- (void)saveTitleOfLastTemplate:(NSString *)title {
    NSString *key = @"BinaryTemplatesLastTemplate";
    if (title) {
        [[NSUserDefaults standardUserDefaults] setObject:title forKey:key];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
    }
}

- (void)openTemplatesFolder:(id __unused)sender {
    NSString *dir = self.templatesFolder;
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSAlert *alert = [NSAlert alertWithError:error];
        [alert runModal];
    } else if (![[NSWorkspace sharedWorkspace] selectFile:nil inFileViewerRootedAtPath:dir]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = NSLocalizedString(@"Failed to open folder.", nil);
        [alert runModal];
    }
    [self.templatesPopUp selectItemWithTitle:self.titleOfLastTemplate];
}

- (void)refresh:(id __unused)sender {
    [self loadTemplates:sender];
    [self rerunTemplate];
}

- (NSArray<NSString *> *)readSupportedTypesAtPath:(NSString *)path {
    static const unsigned long long maxBytes = 512;
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    NSData *data = [handle readDataOfLength:maxBytes];
    NSString *firstBytes = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [handle closeFile];

    static NSRegularExpression *lineRegex;
    static dispatch_once_t lineOnceToken;
    dispatch_once(&lineOnceToken, ^{
        NSString *regexString = @"^\\h*#\\s*HexFiend\\h+Types:\\h*([\\w.-]+(?:[\\h,]+[\\w.-]+)*)\\h*$";
        NSError *error;
        lineRegex = [NSRegularExpression regularExpressionWithPattern:regexString options:NSRegularExpressionAnchorsMatchLines error:&error];
        if (!lineRegex)
            NSLog(@"%@", error);
    });

    static NSRegularExpression *typeRegex;
    static dispatch_once_t typeOnceToken;
    dispatch_once(&typeOnceToken, ^{
        NSError *error;
        typeRegex = [NSRegularExpression regularExpressionWithPattern:@"[\\w.-]+" options:0 error:&error];
        if (!typeRegex)
            NSLog(@"%@", error);
    });

    NSTextCheckingResult *result = [lineRegex firstMatchInString:firstBytes options:0 range:(NSRange){0, firstBytes.length}];

    if (result && result.numberOfRanges == 2) {
        NSRange typesRange = [result rangeAtIndex:1];
        NSString *typesString = [firstBytes substringWithRange:typesRange];
        NSMutableArray *types = [NSMutableArray array];

        [typeRegex enumerateMatchesInString:typesString options:0 range:(NSRange){0, typesString.length} usingBlock:^(NSTextCheckingResult * _Nullable match, __unused NSMatchingFlags flags, __unused BOOL * _Nonnull stop) {
            NSString *type = [typesString substringWithRange:match.range];
            [types addObject:type];
        }];

        return [types copy];
    }

    return nil;
}

- (HFTemplateFile *)defaultTemplateForFileAtURL:(NSURL *)url {
    NSString *type;
    NSError *error;
    [url getResourceValue:&type forKey:NSURLTypeIdentifierKey error:&error];
    NSString *extension = url.pathExtension;

    for (HFTemplateFile *template in self.templates) {
        if ([template.supportedTypes containsObject:type] || [template.supportedTypes containsObject:extension])
            return template;
    }

    return nil;
}

- (void)viewWillAppear {
    NSURL *representedURL = self.view.window.representedURL;
    HFTemplateFile *template = [self defaultTemplateForFileAtURL:representedURL];
    if (template) {
        self.selectedFile = template;
        [self.templatesPopUp selectItemWithTitle:template.name];
        [self rerunTemplate];
    }
}

- (void)loadTemplates:(id __unused)sender {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = self.templatesFolder;
    NSMutableArray<HFTemplateFile*> *templates = [NSMutableArray array];
    for (NSString *filename in [fm enumeratorAtPath:dir]) {
        if ([filename.pathExtension isEqualToString:@"tcl"]) {
            HFTemplateFile *file = [[HFTemplateFile alloc] init];
            file.path = [dir stringByAppendingPathComponent:filename];
            file.name = [[filename lastPathComponent] stringByDeletingPathExtension];
            file.supportedTypes = [self readSupportedTypesAtPath:file.path];
            [templates addObject:file];
        }
    }
    [templates sortUsingDescriptors:@[[[NSSortDescriptor alloc] initWithKey:@"name" ascending:YES]]];
    [self.templatesPopUp removeAllItems];
    NSMenuItem *noneItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"None", nil) action:@selector(noTemplate:) keyEquivalent:@""];
    noneItem.target = self;
    [self.templatesPopUp.menu addItem:noneItem];
    [self.templatesPopUp.menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *itemToSelect = noneItem;
    NSString *titleOfLastTemplate = self.titleOfLastTemplate;
    if (templates.count > 0) {
        for (HFTemplateFile *file in templates) {
            NSMenuItem *templateItem = [[NSMenuItem alloc] initWithTitle:file.name action:@selector(selectTemplateFile:) keyEquivalent:@""];
            templateItem.target = self;
            templateItem.representedObject = file;
            [self.templatesPopUp.menu addItem:templateItem];
            if (titleOfLastTemplate && [titleOfLastTemplate isEqualToString:templateItem.title]) {
                itemToSelect = templateItem;
            }
        }
        [self.templatesPopUp.menu addItem:[NSMenuItem separatorItem]];
    }
    NSMenuItem *refreshItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Refresh", nil) action:@selector(refresh:) keyEquivalent:@""];
    refreshItem.target = self;
    [self.templatesPopUp.menu addItem:refreshItem];
    NSMenuItem *openFolderItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Open Templates Folder", nil) action:@selector(openTemplatesFolder:) keyEquivalent:@""];
    openFolderItem.target = self;
    [self.templatesPopUp.menu addItem:openFolderItem];
    [self.templatesPopUp selectItem:itemToSelect];
    self.templates = templates;
    [self saveTitleOfLastTemplate:itemToSelect.title];
    self.selectedFile = itemToSelect.representedObject;
}

- (void)noTemplate:(id __unused)sender {
    self.selectedFile = nil;
    [self setRootNode:nil error:nil];
    [self saveTitleOfLastTemplate:nil];
}

- (void)selectTemplateFile:(id)sender {
    HFASSERT([sender isKindOfClass:[NSMenuItem class]]);
    NSMenuItem *item = (NSMenuItem *)sender;
    self.selectedFile = item.representedObject;
    [self rerunTemplate];
    [self saveTitleOfLastTemplate:item.title];
}

- (void)rerunTemplate {
    HFASSERT(self.controller != nil);
    [self rerunTemplateWithController:self.controller];
}

- (void)rerunTemplateWithController:(HFController *)controller {
    HFASSERT(controller != nil);
    _controller = controller;
    if (!self.selectedFile || self.controller.contentsLength == 0) {
        return;
    }
    NSString *errorMessage = nil;
    HFTclTemplateController *templateController = [[HFTclTemplateController alloc] init];
    templateController.anchor = self.anchorPosition;
    
    // Change directory to the templates folder so "source" command can use relative paths
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *currentDir = fm.currentDirectoryPath;
    if (![fm changeCurrentDirectoryPath:self.templatesFolder]) {
        NSLog(@"Failed to change directory to %@", self.templatesFolder);
    }
    
    HFTemplateNode *node = [templateController evaluateScript:self.selectedFile.path forController:controller error:&errorMessage];
    
    // Restore current directory
    (void)[fm changeCurrentDirectoryPath:currentDir];
    
    [self setRootNode:node error:errorMessage];
    [self updateSelectionColorRange];
}

- (id)outlineView:(NSOutlineView * __unused)outlineView child:(NSInteger)index ofItem:(id)item {
    HFTemplateNode *node = item != nil ? item : self.node;
    return [node.children objectAtIndex:index];
}

- (NSInteger)outlineView:(NSOutlineView * __unused)outlineView numberOfChildrenOfItem:(id)item {
    HFTemplateNode *node = item != nil ? item : self.node;
    return node.children.count;
}

- (BOOL)outlineView:(NSOutlineView * __unused)outlineView isItemExpandable:(id)item {
    HFTemplateNode *node = item;
    return node.isGroup;
}

- (id)outlineView:(NSOutlineView * __unused)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
    HFTemplateNode *node = item;
    NSString *ident = tableColumn.identifier;
    if ([ident isEqualToString:@"name"]) {
        return node.label;
    }
    if ([ident isEqualToString:@"value"]) {
        return node.value;
    }
    return nil;
}

- (void)collapseValuedGroups {
    NSOutlineView *outlineView = self.outlineView;
    NSInteger numberOfRows = outlineView.numberOfRows;
    for (NSInteger i = numberOfRows - 1; i >= 0; --i) {
        HFTemplateNode *node = [outlineView itemAtRow:i];
        if (node.isGroup && node.value) {
            [outlineView collapseItem:node];
        }
    }
}

- (void)setRootNode:(HFTemplateNode *)node error:(NSString *)error {
    if (error != nil) {
        self.node = nil;
        self.errorTextField.stringValue = error;
        self.errorTextField.hidden = NO;
    } else {
        self.node = node;
        self.errorTextField.hidden = YES;
    }
    [self.outlineView reloadData];
    [self.outlineView expandItem:nil expandChildren:YES];
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"BinaryTemplatesAutoCollapseValuedGroups"]) {
        [self collapseValuedGroups];
    }
}

- (NSColor *)selectionColor {
    NSColor *color = [NSColor lightGrayColor];
    NSData *colorData = [[NSUserDefaults standardUserDefaults] objectForKey:@"BinaryTemplateSelectionColor"];
    if (colorData && [colorData isKindOfClass:[NSData class]]) {
        NSColor *tempColor = [NSUnarchiver unarchiveObjectWithData:colorData];
        if (tempColor && [tempColor isKindOfClass:[NSColor class]]) {
            color = tempColor;
        }
    }
    return color;
}

- (void)updateSelectionColor {
    if (self.colorRange) {
        self.colorRange.color = [self selectionColor];
        [self.controller colorRangesDidChange];
    }
}

- (void)updateSelectionColorRange {
    NSInteger row = self.outlineView.selectedRow;
    if (row != -1) {
        HFTemplateNode *node = [self.outlineView itemAtRow:row];
        if (!self.colorRange) {
            self.colorRange = [[HFColorRange alloc] init];
            self.colorRange.color = [self selectionColor];
            [self.controller.colorRanges addObject:self.colorRange];
        }
        self.colorRange.range = [HFRangeWrapper withRange:node.range];
        [self.controller colorRangesDidChange];
    } else if (self.colorRange) {
        [self.controller.colorRanges removeObject:self.colorRange];
        [self.controller colorRangesDidChange];
        self.colorRange = nil;
    }
}

- (void)outlineViewSelectionDidChange:(NSNotification * __unused)notification {
    [self updateSelectionColorRange];
    
    if (self.outlineView.numberOfSelectedRows == 1) {
        NSInteger action = [[NSUserDefaults standardUserDefaults] integerForKey:@"BinaryTemplatesSingleClickAction"];
        switch (action) {
            case 0: // do nothing
                break;
            case 1: // scroll to offset
                [self jumpToField:nil];
                break;
            case 2: // select bytes
                [self selectBytes:nil];
                break;
            default:
                NSLog(@"Unknown single click action %ld", action);
        }
    }
}

- (NSMenu *)outlineView:(NSOutlineView *)sender menuForEvent:(NSEvent *)event {
    NSMenu *menu = [[NSMenu alloc] init];
    menu.autoenablesItems = NO;
    NSPoint loc = [sender convertPoint:event.locationInWindow fromView:nil];
    NSInteger row = [sender rowAtPoint:loc];
    [sender selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    id obj = row != -1 ? [sender itemAtRow:row] : nil;
    NSMenuItem *item;

    item = [menu addItemWithTitle:NSLocalizedString(@"Scroll to Offset", nil) action:@selector(jumpToField:) keyEquivalent:@""];
    item.target = self;
    item.enabled = obj != nil;
    
    item = [menu addItemWithTitle:NSLocalizedString(@"Copy Value", nil) action:@selector(copyValue:) keyEquivalent:@""];
    item.target = self;
    item.enabled = obj != nil;
    
    item = [menu addItemWithTitle:NSLocalizedString(@"Select Bytes", nil) action:@selector(selectBytes:) keyEquivalent:@""];
    item.target = self;
    item.enabled = obj != nil;

    return menu;
}

- (void)outlineViewDoubleAction:(id)sender {
    HFASSERT(sender == self.outlineView);
    NSInteger row = self.outlineView.clickedRow;
    if (row != -1) {
        NSInteger action = [[NSUserDefaults standardUserDefaults] integerForKey:@"BinaryTemplatesDoubleClickAction"];
        switch (action) {
            case 0: // do nothing
                break;
            case 1: // scroll to offset
                [self jumpToField:sender];
                break;
            case 2: // select bytes
                [self selectBytes:sender];
                break;
            default:
                NSLog(@"Unknown double click action %ld", action);
        }
    }
}

- (void)jumpToField:(id __unused)sender {
    HFTemplateNode *node = [self.outlineView itemAtRow:[self.outlineView selectedRow]];
    HFRange range = HFRangeMake(node.range.location, 0);
    [self.controller setSelectedContentsRanges:@[[HFRangeWrapper withRange:range]]];
    [self.controller maximizeVisibilityOfContentsRange:range];
}

- (void)anchorTo:(NSUInteger)position {
    self.anchorPosition = position;
    [self rerunTemplate];
}

- (void)copyValue:(id __unused)sender {
    HFTemplateNode *node = [self.outlineView itemAtRow:[self.outlineView selectedRow]];
    NSPasteboard *pboard = [NSPasteboard generalPasteboard];
    [pboard clearContents];
    [pboard setString:node.value forType:NSPasteboardTypeString];
}

- (void)selectBytes:(id __unused)sender {
    HFTemplateNode *node = [self.outlineView itemAtRow:[self.outlineView selectedRow]];
    [self.controller setSelectedContentsRanges:@[[HFRangeWrapper withRange:node.range]]];
}

- (void)copy:(id)sender {
    // NSResponder chain from Edit > Copy
    if (self.outlineView.numberOfSelectedRows > 0) {
        [self copyValue:sender];
    }
}

@end
