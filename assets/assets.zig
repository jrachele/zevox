const root_path = "assets/";

pub const fonts = struct {
    pub const roboto_medium = struct {
        pub const path = root_path ++ "fonts/Roboto-Medium.ttf";
        pub const bytes = @embedFile("fonts/Roboto-Medium.ttf");
    };
};
