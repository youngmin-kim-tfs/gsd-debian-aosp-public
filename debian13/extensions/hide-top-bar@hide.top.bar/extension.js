import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';

export default class HideTopBarExtension extends Extension {
    constructor(metadata) {
        super(metadata);
    }

    enable() {
        Main.panel.hide();
    }

    disable() {
        Main.panel.show();
    }
}
