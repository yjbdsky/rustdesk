#rustup target list|grep windows
#rustup target add x86_64-pc-windows-msvc

#rustup toolchain install stable-x86_64-pc-windows-gnu
#rustup target add x86_64-pc-windows-gnu --toolchain=stable

# cat ~/.cargo/config
#[target.x86_64-pc-windows-gnu]
#linker = "x86_64-w64-mingw32-gcc"
#ar = "x86_64-w64-mingw32-gcc-ar"

cargo build --release --target x86_64-pc-windows-msvc