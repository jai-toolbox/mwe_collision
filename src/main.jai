/*

so we still occasionally get slow frames, this should not be happening in such a simple project.

after looking at the program through intel gpa it seems like its dwm that's being slow and it's not really my fault.

When I do exclusive fullscreen it seems to work better, less slow frames compared to before so that's good. 

At the same time it should run ok in windowed mode and slightly frustrated that it doesn't, I guess we can cook up a mwe at some point.

*/


#import "tbx/model_loading";
#import "tbx/geometry";
#import "tbx/opengl";
#import "tbx/camera";
#import "tbx/movement";
#import "tbx/collision";
#import "tbx/math";
#import "tbx/engine";
#import "tbx/rectangle";
#import "tbx/physics";
#import "tbx/time";

#import "tbx/section_logger"()(false);
// #import "tbx/section_logger";

#import "Basic";
#import "GL";
#import "File";
#import "Random";
#import "Math";
#import "Window_Creation";
#import "GetRect";


Simp :: #import "Simp";
using,except(Shader) Simp;

Input :: #import "Input";

convert_obj_to_indexed_meshes :: (obj_data: *Obj_Data) -> [..] Indexed_Mesh {
    meshes: [..] Indexed_Mesh;
    
    for *obj_object : obj_data.all_objects {
        mesh: Indexed_Mesh;
        current_index: u32 = 0;
        
        for *face : obj_object.faces {
            if face.face_vertices.count < 3 continue;
            
            first_index := current_index;
            
            for *fv : face.face_vertices {
                array_add(*mesh.positions, obj_data.all_positions[fv.position_index]);
                
                if fv.texture_coordinate_index >= 0 {
                    array_add(*mesh.texture_coordinates, obj_data.all_texture_coordinates[fv.texture_coordinate_index]);
                } else {
                    array_add(*mesh.texture_coordinates, .{0, 0});
                }
                
                if fv.normal_index >= 0 {
                    array_add(*mesh.normals, obj_data.all_normals[fv.normal_index]);
                } else {
                    array_add(*mesh.normals, .{0, 1, 0});
                }

                r1 := random_get_zero_to_one();
                r2 := random_get_zero_to_one();
                r3 := random_get_zero_to_one();
                random_color := Vector3.{r1, r2, r3};

                array_add(*mesh.rgb_colors, random_color);

                current_index += 1;
            }
            
            for i : 1..face.face_vertices.count-2 {
                array_add(*mesh.indices, first_index);
                array_add(*mesh.indices, first_index + cast(u32) i);
                array_add(*mesh.indices, first_index + cast(u32) i + 1);
            }
        }
        
        array_add(*meshes, mesh);
    }
    
    return meshes;
}

Renderable :: struct {
    indexed_mesh : Indexed_Mesh;
    local_to_world_index : u32;
    render_object_index : u32;
};

Character :: struct {
    using #as cg : Collision_Geometry;
    using r : Renderable;
}

main :: () {
    windowed_program_3d : Windowed_Program_3D;
    windowed_program_3d.movement_mode = .MANUAL;
    windowed_program_3d.camera_mode = .FIRST_PERSON;
    windowed_program_3d.window_width = 1000;
    windowed_program_3d.window_height = 1000;
    windowed_program_3d.window_name = "mwe_collision";

    windowed_program_3d.camera.offset = Y3 * 1.75 * 0.25;

    init(*windowed_program_3d);

    obj_data := load_obj("data/up_high.obj");

    meshes := convert_obj_to_indexed_meshes(*obj_data);

    map : Collision_Geometries;

    movement_mode := Movement_Mode.FPS;

    for meshes {
        cg : Collision_Geometry;
        cg.indexed_triangle_positions.indices = it.indices;
        cg.indexed_triangle_positions.positions = it.positions;

        cg.aabb = create_aabb_from_positions(cg.indexed_triangle_positions.positions);

        array_add(*map.indexed_triangle_positions,cg.indexed_triangle_positions);
        array_add(*map.aabbs,cg.aabb);
    }

    character : Character;
    character.indexed_triangle_positions = create_box(ZERO3, 0.4, 1.75, 0.4); 
    character.aabb = create_aabb_from_positions(character.indexed_triangle_positions.positions);
    character.indexed_mesh.indices = character.indexed_triangle_positions.indices;
    character.indexed_mesh.positions = character.indexed_triangle_positions.positions;

    for 1..character.indexed_mesh.positions.count array_add(*character.indexed_mesh.rgb_colors, .{0, .5, .5});

    character_local_to_world_index: u32;

    windowed_program_3d.camera.position = Y3 * 15;
    velocity : Vector3;
    on_ground : bool;

    movement_state : CPMA_Movement_State;

    renderables : [..] Renderable;
    
    count := 10;
    for meshes {
        renderable: Renderable;
        renderable.indexed_mesh = it;
        
        renderable.render_object_index, renderable.local_to_world_index = buffer_object(*windowed_program_3d.camera_per_object_transform_color_renderer, renderable.indexed_mesh.indices, renderable.indexed_mesh.positions, renderable.indexed_mesh.rgb_colors);

        array_add(*renderables, renderable);

        count += 1;
    }

    quit := false;
    while !windowed_program_3d.end_program {

        mark_frame_start(*windowed_program_3d);

        start_section(*windowed_program_3d.section_timer, "tick");

        start_section(*windowed_program_3d.section_timer, "per_frame_update");
        if is_key_just_pressed(xx #char "M")
            toggle_menu(*windowed_program_3d);
        per_frame_update(*windowed_program_3d);
        end_section(*windowed_program_3d.section_timer, "per_frame_update");

        start_section(*windowed_program_3d.section_timer, "shader_setup");
        glUseProgram(windowed_program_3d.absolute_position_color_renderer.shader_program_gl_handle);
        set_aspect_ratio_uniform(*windowed_program_3d.absolute_position_color_renderer, .{xx windowed_program_3d.window_width, xx windowed_program_3d.window_height});
        glUseProgram(0);
        end_section(*windowed_program_3d.section_timer, "shader_setup");

        if (windowed_program_3d.current_menu == .NONE) {

            start_section(*windowed_program_3d.section_timer, "queue_renderables");
            for renderables queue_render(*windowed_program_3d.camera_per_object_transform_color_renderer, it.render_object_index);
            end_section(*windowed_program_3d.section_timer, "queue_renderables");

            start_section(*windowed_program_3d.section_timer, "movement_update");
            fpmi := sample_first_person_movement_input();
            update(*movement_state, fpmi, *windowed_program_3d.camera.position, *velocity, *on_ground, get_forward(*windowed_program_3d.camera), *map, windowed_program_3d.delta_time);
            end_section(*windowed_program_3d.section_timer, "movement_update");

            start_section(*windowed_program_3d.section_timer, "scene_render");
            glUseProgram(windowed_program_3d.camera_per_object_transform_color_renderer.shader_program_gl_handle);
            Simp.update_window(windowed_program_3d.window);
            Simp.clear_render_target(.15, .08, .08, 1);
            glDepthMask(GL_TRUE);
            glEnable(GL_DEPTH_TEST);
            glClear(GL_DEPTH_BUFFER_BIT);
            render(*windowed_program_3d.camera_per_object_transform_color_renderer);
            end_section(*windowed_program_3d.section_timer, "scene_render");

            start_section(*windowed_program_3d.section_timer, "hud_render");
            {
                ctx := context;
                ctx.allocator = temp;

                push_context ctx {

                    raw_geom := create_annulus(ZERO3, Z3, 0.01, 0.02, 8);
                    itpc := create_itpc_with_color(raw_geom, .{0.5, 0.8, 0.1});
                    immediate_render(*windowed_program_3d.absolute_position_color_renderer, itpc.indices, itpc.positions, itpc.rgb_colors);

                    dial_radius := 0.1;
                    dial_border_thickness := 0.005;
                    dial_color := Vector3.{0.5, 0.8, 0.1};

                    movement_dial_center := Vector2.{0.65, -0.8};
                    movement_dial_geom := create_annulus(make_vector3(movement_dial_center, 0), Z3, dial_radius - dial_border_thickness, dial_radius, 8);
                    movement_dial_itpc := create_itpc_with_color(movement_dial_geom, dial_color);
                    immediate_render(*windowed_program_3d.absolute_position_color_renderer, movement_dial_itpc.indices, movement_dial_itpc.positions, movement_dial_itpc.rgb_colors);

                    forward : float = 0.0;
                    right   : float = 0.0;
                    if is_key_down(xx #char "W") forward += 1.0;
                    if is_key_down(xx #char "S") forward -= 1.0;
                    if is_key_down(xx #char "D") right   += 1.0;
                    if is_key_down(xx #char "A") right   -= 1.0;

                    input_dir := Vector2.{right, forward};
                    input_len := length(input_dir);

                    if input_len > 0.001 {
                        normalized_dir := input_dir / input_len;
                        clamped_len := min(input_len, 1.0);
                        arrow_tip := movement_dial_center + normalized_dir * clamped_len * (dial_radius - dial_border_thickness);
                        arrow_geom := create_2d_arrow(movement_dial_center, arrow_tip, 0.008);
                        arrow_itpc := create_itpc_with_color(arrow_geom, dial_color);
                        immediate_render(*windowed_program_3d.absolute_position_color_renderer, arrow_itpc.indices, arrow_itpc.positions, arrow_itpc.rgb_colors);
                    }

                    mouse_dial_center := Vector2.{0.9, -0.8};
                    mouse_dial_geom := create_annulus(make_vector3(mouse_dial_center, 0), Z3, dial_radius - dial_border_thickness, dial_radius, 8);
                    mouse_dial_itpc := create_itpc_with_color(mouse_dial_geom, dial_color);
                    immediate_render(*windowed_program_3d.absolute_position_color_renderer, mouse_dial_itpc.indices, mouse_dial_itpc.positions, mouse_dial_itpc.rgb_colors);

                    mouse_sensitivity_scale :: 10.0;
                    mouse_dir := Vector2.{
                        cast(float) windowed_program_3d.last_mouse_delta_x / mouse_sensitivity_scale,
                       -cast(float) windowed_program_3d.last_mouse_delta_y / mouse_sensitivity_scale
                    };
                    mouse_len := length(mouse_dir);

                    if mouse_len > 0.001 {
                        normalized_mouse := mouse_dir / mouse_len;
                        clamped_mouse_len := min(mouse_len, 1.0);
                        mouse_arrow_tip := mouse_dial_center + normalized_mouse * clamped_mouse_len * (dial_radius - dial_border_thickness);
                        mouse_arrow_geom := create_2d_arrow(mouse_dial_center, mouse_arrow_tip, 0.008);
                        mouse_arrow_itpc := create_itpc_with_color(mouse_arrow_geom, dial_color);
                        immediate_render(*windowed_program_3d.absolute_position_color_renderer, mouse_arrow_itpc.indices, mouse_arrow_itpc.positions, mouse_arrow_itpc.rgb_colors);
                    }
                }
            }
            end_section(*windowed_program_3d.section_timer, "hud_render");

            start_section(*windowed_program_3d.section_timer, "ui_render");
            context.simp.current_shader = null;
            render_tick_stats(*windowed_program_3d);
            render_performance_graph(*windowed_program_3d);
            render_section_bar_graph(*windowed_program_3d);
            {
                label_theme := windowed_program_3d.my_theme.label_theme;
                rect_height := 0.1;
                rect_width := 0.4;
                r_vel := get_rect_normalized(create_rectangle(-1, 1 - rect_height, rect_width, rect_height, .TOP_LEFT), xx windowed_program_3d.window_width, xx windowed_program_3d.window_height);
                horizontal_vel := velocity;
                horizontal_vel.y = 0;
                label(r_vel, tprint("% m/s (h)", formatFloat(length(horizontal_vel), trailing_width=2, zero_removal=.NO)), *label_theme);
            }
            render_camera_stats(*windowed_program_3d);
            render_iteration(*windowed_program_3d);
            end_section(*windowed_program_3d.section_timer, "ui_render");

            start_section(*windowed_program_3d.section_timer, "swap_and_finish");
            swap_buffers(windowed_program_3d.window, false);
            // glFinish();
            end_section(*windowed_program_3d.section_timer, "swap_and_finish");

        } else {
            start_section(*windowed_program_3d.section_timer, "menu_render");
            context.simp.current_shader = null;
            clear_render_target(.35, .35, .35, 1);
            render_menus(*windowed_program_3d.wp);
            swap_buffers(windowed_program_3d.window, false);
            end_section(*windowed_program_3d.section_timer, "menu_render");
        }

        start_section(*windowed_program_3d.section_timer, "fps_sleep");
        sleep_to_maintain_max_fps(*windowed_program_3d);
        end_section(*windowed_program_3d.section_timer, "fps_sleep");

        end_section(*windowed_program_3d.section_timer, "tick");

        mark_frame_end(*windowed_program_3d);
    }
}

